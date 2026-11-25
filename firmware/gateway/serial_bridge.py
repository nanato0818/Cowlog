"""Durable JSON-lines -> Cowlog HTTPS bridge; USB prototype, not LoRa firmware."""
from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
import threading
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from urllib.parse import urlparse


class Outbox:
    def __init__(self, path: str):
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(path)
        self.db.execute('PRAGMA journal_mode=WAL')
        self.db.execute('''CREATE TABLE IF NOT EXISTS outbox (
            device_id TEXT, stream_id INTEGER, seq INTEGER, body TEXT NOT NULL,
            PRIMARY KEY(device_id,stream_id,seq))''')
        self.db.commit()

    def enqueue(self, record: dict):
        if not isinstance(record, dict):
            raise ValueError('record must be an object')
        device, stream, seq = (record.get(k) for k in ('device_id','stream_id','seq'))
        if not isinstance(device,str) or not device or len(device)>64:
            raise ValueError('invalid device_id')
        if any(type(v) is not int or not 0<=v<=2**32-1 for v in (stream,seq)):
            raise ValueError('invalid stream_id/seq')
        body = json.dumps(record, allow_nan=False, separators=(',',':'))
        with self.db:
            self.db.execute('INSERT INTO outbox VALUES (?,?,?,?) ON CONFLICT DO NOTHING',
                            (device,stream,seq,body))

    def flush(self, url: str, token: str, opener=urlopen) -> int:
        rows = self.db.execute('SELECT rowid,body FROM outbox ORDER BY rowid LIMIT 100').fetchall()
        if not rows:
            return 0
        payload=json.dumps({'records':[json.loads(row[1]) for row in rows]}).encode()
        request=Request(url.rstrip('/')+'/v1/measurements',data=payload,
                        headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
        with opener(request,timeout=15) as response:
            result=json.load(response)
        accepted,duplicates=result.get('accepted'),result.get('duplicates')
        if (type(accepted) is not int or type(duplicates) is not int or
                min(accepted,duplicates)<0 or accepted+duplicates!=len(rows)):
            raise ValueError('invalid acknowledgement; batch kept for retry')
        with self.db:
            self.db.executemany('DELETE FROM outbox WHERE rowid=?',[(row[0],) for row in rows])
        return len(rows)

    def close(self):
        self.db.close()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    source=parser.add_mutually_exclusive_group(required=True)
    source.add_argument('--port',help='USB serial port; requires pyserial')
    source.add_argument('--input',help='JSONL file or - for stdin (replay/test)')
    parser.add_argument('--outbox',default='cowlog-outbox.sqlite3')
    parser.add_argument('--api-url',default=os.environ.get('COWLOG_API_URL',''))
    args=parser.parse_args()
    if urlparse(args.api_url).scheme!='https' or not urlparse(args.api_url).hostname:
        parser.error('COWLOG_API_URL or --api-url must be HTTPS')
    token=os.environ.get('COWLOG_INGEST_TOKEN','')
    if not token:
        parser.error('set COWLOG_INGEST_TOKEN')
    outbox=Outbox(args.outbox)
    # Receive and durably queue independently of slow/cloud-offline requests.
    stop=threading.Event()
    def uploader():
        pending=Outbox(args.outbox)
        try:
            while not stop.is_set():
                try:
                    if pending.flush(args.api_url,token):
                        continue
                except HTTPError as error:
                    print(f'Upload HTTP {error.code}; records retained',file=sys.stderr)
                except Exception as error:
                    print(f'Upload failed ({type(error).__name__}); records retained',file=sys.stderr)
                stop.wait(5)
        finally:
            pending.close()
    worker=threading.Thread(target=uploader,daemon=True)
    worker.start()
    try:
        if args.port:
            try:
                import serial
            except ImportError:
                parser.error('USB input needs pyserial: python3 -m pip install pyserial')
            source_stream=serial.Serial(args.port,115200,timeout=1)
        else:
            source_stream=sys.stdin if args.input=='-' else open(args.input,encoding='utf-8')
        with source_stream:
            lines = iter(lambda: source_stream.readline(), None) if args.port else source_stream
            for line in lines:
                if isinstance(line,bytes):
                    line=line.decode('utf-8',errors='replace')
                if not line.strip().startswith('{'):
                    continue  # GNSS debug messages may share the serial connection.
                try:
                    outbox.enqueue(json.loads(line))
                except (ValueError,TypeError) as error:
                    print(f'Invalid JSON record ({type(error).__name__}); skipped',file=sys.stderr)
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        worker.join(timeout=17)
        # Finite replay files should also attempt their final queued batch.
        if not args.port:
            try:
                while outbox.flush(args.api_url,token):
                    pass
            except Exception as error:
                print(f'Final upload failed ({type(error).__name__}); records retained',file=sys.stderr)
        outbox.close()

if __name__=='__main__':
    main()
