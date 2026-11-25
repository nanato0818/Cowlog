"""Number management: authorization, conflicts and preservation of telemetry."""
import json
import tempfile
import threading
import unittest
from pathlib import Path
from datetime import timedelta
from http.server import ThreadingHTTPServer
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from app import Handler, init_db, ingest, collars, set_collar_number, dashboard, history, NumberConflict, utcnow, iso, register_cow, register_collar, JST

class NumberTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = str(Path(self.tmp.name)/'test.sqlite3')
        init_db(self.db)
        self.now = utcnow()
        for device in ('device-A','device-B'):
            ingest(self.db,[dict(device_id=device,stream_id=1,seq=1,
                measured_at=iso(self.now),latitude=35.0,longitude=139.0,
                activity_seconds=0,coverage_seconds=0,interval_seconds=15)])
    def tearDown(self): self.tmp.cleanup()

    def test_discovery_rename_preserves_identity_history_and_leading_zeros(self):
        self.assertEqual(len(collars(self.db)['collars']),2)
        self.assertIsNone(collars(self.db)['collars'][0]['number'])
        set_collar_number(self.db,'device-A','0007',None)
        before=dashboard(self.db)['cows'][0]
        day=self.now.astimezone(JST).strftime('%Y-%m-%d')
        old_history=history(self.db,before['id'],day)
        set_collar_number(self.db,'device-A','0020','0007')
        after=dashboard(self.db)['cows'][0]
        self.assertEqual(after['number'],'0020')
        self.assertEqual(before['id'],after['id'])
        self.assertEqual(history(self.db,after['id'],day),old_history)
        self.assertEqual(len(old_history['measurements']),1)
        # The same request can be retried after a lost HTTP response.
        set_collar_number(self.db,'device-A','0020','0007')

    def test_duplicate_stale_and_invalid_writes_do_not_change_existing_number(self):
        set_collar_number(self.db,'device-A','0007',None)
        with self.assertRaises(NumberConflict): set_collar_number(self.db,'device-B','0007',None)
        with self.assertRaises(NumberConflict): set_collar_number(self.db,'device-A','0008',None)
        for number in ('','A-01','１２','1'*13,7):
            with self.assertRaises(ValueError): set_collar_number(self.db,'device-A',number,'0007')
        with self.assertRaises(LookupError): set_collar_number(self.db,'unknown','0009',None)
        self.assertEqual(dashboard(self.db)['cows'][0]['number'],'0007')

    def test_numbering_a_detached_legacy_collar_does_not_steal_old_history(self):
        register_cow(self.db,'legacy','old','device-A',self.now-timedelta(hours=2),'0100')
        register_cow(self.db,'legacy','old',None,self.now-timedelta(hours=1),'0100')
        ingest(self.db,[dict(device_id='device-A',stream_id=1,seq=2,
            measured_at=iso(self.now-timedelta(minutes=90)),latitude=34.0,longitude=139.0,
            activity_seconds=0,coverage_seconds=0,interval_seconds=15)])
        # The original sample was measured after detachment, belongs to new use.
        set_collar_number(self.db,'device-A','0200',None)
        new=next(c for c in dashboard(self.db)['cows'] if c['number']=='0200')
        self.assertEqual(new['latest_position']['latitude'],35.0)
        day=self.now.astimezone(JST).strftime('%Y-%m-%d')
        recent=history(self.db,new['id'],day)['measurements']
        self.assertTrue(all(r['seq']==1 for r in recent))
        old_day=(self.now-timedelta(minutes=90)).astimezone(JST).strftime('%Y-%m-%d')
        self.assertEqual(history(self.db,'legacy',old_day)['measurements'][0]['seq'],2)

    def test_display_style_is_explicit_persisted_and_conflict_checked(self):
        set_collar_number(self.db,'device-A','0007',None,'brown','unknown')
        self.assertEqual(dashboard(self.db)['cows'][0]['cow_style'],'brown')
        self.assertEqual(collars(self.db)['collars'][0]['cow_style'],'brown')
        set_collar_number(self.db,'device-A','0007',None,'brown','unknown') # retry
        init_db(self.db) # a restart/migration preserves the selected appearance
        set_collar_number(self.db,'device-A','0008','0007') # old clients preserve it
        self.assertEqual(dashboard(self.db)['cows'][0]['cow_style'],'brown')
        with self.assertRaises(NumberConflict):
            set_collar_number(self.db,'device-A','0008','0008','holstein','unknown')
        with self.assertRaises(ValueError):
            set_collar_number(self.db,'device-A','0008','0008','guessed','brown')

    def test_manual_registration_has_no_fabricated_telemetry_and_retries_safely(self):
        result=register_collar(self.db,'collar-new','0099','brown')
        self.assertTrue(result['created'])
        self.assertFalse(register_collar(self.db,'collar-new','0099','brown')['created'])
        cow=dashboard(self.db)['cows'][0]
        self.assertEqual(cow['status'],'no_data')
        self.assertIsNone(cow['latest_position'])
        self.assertEqual(cow['cow_style'],'brown')
        with self.assertRaises(NumberConflict): register_collar(self.db,'different','0099')
        with self.assertRaises(NumberConflict): register_collar(self.db,'collar-new','0100')
        with self.assertRaises(ValueError): register_collar(self.db,'bad/id','0100')

    def test_http_read_and_ingest_tokens_cannot_change_numbers(self):
        db=self.db
        class TestHandler(Handler):
            db_path=db
            read_token='read';ingest_token='ingest';manage_token='manage'
            def log_message(self,*args): pass
        server=ThreadingHTTPServer(('127.0.0.1',0),TestHandler)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        url=f'http://127.0.0.1:{server.server_port}'
        def request(token, body=None):
            req=Request(url+'/v1/collars/device-A/number',method='PUT',
                headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'},
                data=json.dumps(body or {'number':'0007','expected_number':None}).encode())
            return json.load(urlopen(req))
        try:
            for token in ('read','ingest',''):
                with self.assertRaises(HTTPError) as e: request(token)
                self.assertEqual(e.exception.code,401)
            req=Request(url+'/v1/collars',headers={'Authorization':'Bearer read'})
            self.assertEqual(len(json.load(urlopen(req))['collars']),2)
            self.assertEqual(request('manage')['saved_to'],'server')
            with self.assertRaises(HTTPError) as e: request('manage',{'number':'0008'})
            self.assertEqual(e.exception.code,400)
            with self.assertRaises(HTTPError) as e: request('manage',{'number':'0008','expected_number':None})
            self.assertEqual(e.exception.code,409)
        finally:
            server.shutdown();server.server_close();thread.join(timeout=2)
