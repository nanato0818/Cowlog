import io
import json
import tempfile
import unittest
from pathlib import Path
from urllib.error import URLError
from serial_bridge import Outbox

class BridgeTests(unittest.TestCase):
    def test_network_failure_restart_and_acknowledged_retry(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=str(Path(tmp)/'queue.sqlite3')
            record={'device_id':'collar-01','stream_id':1,'seq':7}
            queue=Outbox(path);queue.enqueue(record);queue.enqueue(record)
            def offline(*args,**kwargs): raise URLError('offline')
            with self.assertRaises(URLError): queue.flush('https://farm.example','token',offline)
            queue.close();queue=Outbox(path)
            def success(request,**kwargs):
                self.assertEqual(json.loads(request.data)['records'],[record])
                return io.BytesIO(b'{"accepted":0,"duplicates":1}')
            self.assertEqual(queue.flush('https://farm.example','token',success),1)
            self.assertEqual(queue.flush('https://farm.example','token',success),0)
            queue.close()
    def test_invalid_acknowledgement_keeps_batch(self):
        with tempfile.TemporaryDirectory() as tmp:
            queue=Outbox(str(Path(tmp)/'queue.sqlite3'))
            queue.enqueue({'device_id':'collar','stream_id':1,'seq':1})
            with self.assertRaises(ValueError):
                queue.flush('https://farm.example','token',lambda *a,**k:io.BytesIO(b'{"accepted":0,"duplicates":0}'))
            self.assertEqual(queue.db.execute('SELECT COUNT(*) FROM outbox').fetchone()[0],1)
            queue.close()
if __name__=='__main__': unittest.main()
