"""Synthetic contract test; does not substitute for real GNSS field testing."""
import importlib.util
import json
import tempfile
import threading
import unittest
from datetime import timedelta
from http.server import ThreadingHTTPServer
from pathlib import Path
from urllib.request import Request,urlopen
from app import Handler,init_db,register_cow,utcnow,iso

spec=importlib.util.spec_from_file_location('serial_bridge',Path(__file__).resolve().parents[2]/'firmware/gateway/serial_bridge.py')
bridge=importlib.util.module_from_spec(spec);spec.loader.exec_module(bridge)

class PipelineTests(unittest.TestCase):
    def test_gnss_json_through_outbox_http_database_and_app_contract(self):
        with tempfile.TemporaryDirectory() as tmp:
            db=str(Path(tmp)/'api.sqlite3');init_db(db)
            now=utcnow()
            register_cow(db,'cow-A','牛 A-0007','collar-ABC',now-timedelta(days=1),'A-0007','0012345678')
            class TestHandler(Handler):
                db_path=db
                read_token='read-test'
                ingest_token='ingest-test'
                def log_message(self,*args): pass
            server=ThreadingHTTPServer(('127.0.0.1',0),TestHandler)
            thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
            root=f'http://127.0.0.1:{server.server_port}'
            queue=bridge.Outbox(str(Path(tmp)/'outbox.sqlite3'))
            try:
                # Same JSON shape as the new GNSS-only firmware mode.
                sample={'device_id':'collar-ABC','stream_id':17,'seq':1,
                    'measured_at':iso(now),'latitude':34.26712,'longitude':133.20581,
                    'gps_accuracy_m':None,'hdop':1.3,'satellites':12,
                    'activity_seconds':0,'coverage_seconds':0,'interval_seconds':15}
                queue.enqueue(sample)
                self.assertEqual(queue.flush(root,'ingest-test'),1)
                request=Request(root+'/v1/dashboard',headers={'Authorization':'Bearer read-test'})
                with urlopen(request) as response: cow=json.load(response)['cows'][0]
                self.assertEqual(cow['profile']['herd_number'],'A-0007')
                self.assertEqual(cow['latest_position']['latitude'],sample['latitude'])
                self.assertEqual(cow['latest_position']['longitude'],sample['longitude'])
                self.assertIsNone(cow['latest_position']['accuracy_m'])
                self.assertEqual(cow['latest_position']['hdop'],1.3)
                self.assertEqual(cow['latest_position']['satellites'],12)
                self.assertEqual(cow['status'],'insufficient')
                self.assertIsNone(cow['activity_ratio'])
            finally:
                queue.close();server.shutdown();server.server_close();thread.join(timeout=2)
if __name__=='__main__': unittest.main()
