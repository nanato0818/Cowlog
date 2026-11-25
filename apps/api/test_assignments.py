import sqlite3
import tempfile
import unittest
from pathlib import Path
from datetime import timedelta
from app import register_cow, dashboard, history, ingest, init_db
from test_app import record, NOW

class AssignmentTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.db=str(Path(self.tmp.name)/'test.sqlite3')
        init_db(self.db)
    def tearDown(self):
        self.tmp.cleanup()
    def test_reused_collar_and_delayed_upload_stay_with_original_cow(self):
        register_cow(self.db,'uuid-A','牛 A-001','collar-01',NOW-timedelta(days=2), 'A-001','0012345678')
        old=record(1,NOW-timedelta(hours=2))
        register_cow(self.db,'uuid-B','牛 0007','collar-01',NOW-timedelta(hours=1),'0007')
        new=record(2,NOW)
        # Delayed records arrive after the physical swap.
        ingest(self.db,[old,new],NOW)
        a=history(self.db,'uuid-A','2026-09-24')['measurements']
        b=history(self.db,'uuid-B','2026-09-24')['measurements']
        self.assertEqual([row['seq'] for row in a],[1])
        self.assertEqual([row['seq'] for row in b],[2])
        cows={c['id']:c for c in dashboard(self.db,NOW)['cows']}
        self.assertIsNone(cows['uuid-A']['device_id'])
        self.assertEqual(cows['uuid-A']['profile']['individual_number'],'0012345678')
        self.assertEqual(cows['uuid-B']['profile']['herd_number'],'0007')
    def test_second_collar_preserves_same_cow_history(self):
        register_cow(self.db,'cow','牛','collar-01',NOW-timedelta(days=1))
        ingest(self.db,[record(1,NOW-timedelta(hours=2))],NOW)
        register_cow(self.db,'cow','牛','collar-new',NOW-timedelta(hours=1))
        current=dashboard(self.db,NOW)['cows'][0]
        self.assertIsNone(current['battery_percent'])
        self.assertIsNone(current['latest_position'])
        self.assertEqual(current['status'],'no_data')
        next_record=record(2,NOW);next_record['device_id']='collar-new'
        ingest(self.db,[next_record],NOW)
        self.assertEqual(len(history(self.db,'cow','2026-09-24')['measurements']),2)
    def test_no_attachment_does_not_claim_old_records(self):
        ingest(self.db,[record(1,NOW-timedelta(days=1))],NOW)
        register_cow(self.db,'cow','牛','collar-01',NOW-timedelta(hours=1))
        self.assertEqual(history(self.db,'cow','2026-09-23')['measurements'],[])
    def test_backdated_overlap_rolls_back(self):
        register_cow(self.db,'a','A','collar-01',NOW-timedelta(hours=2))
        with self.assertRaises(ValueError):
            register_cow(self.db,'b','B','collar-01',NOW-timedelta(hours=3))
        self.assertEqual([c['id'] for c in dashboard(self.db,NOW)['cows']],['a'])
    def test_legacy_db_migrates_idempotently(self):
        legacy=str(Path(self.tmp.name)/'legacy.sqlite3')
        with sqlite3.connect(legacy) as db:
            db.execute('CREATE TABLE cows(id TEXT PRIMARY KEY,name TEXT NOT NULL,device_id TEXT NOT NULL UNIQUE)')
            db.execute("INSERT INTO cows VALUES('a','旧登録','collar-01')")
        init_db(legacy);init_db(legacy)
        ingest(legacy,[record(1,NOW-timedelta(hours=2))],NOW)
        register_cow(legacy,'b','新登録','collar-01',NOW-timedelta(hours=1))
        self.assertEqual(len(history(legacy,'a','2026-09-24')['measurements']),1)
        self.assertEqual(history(legacy,'b','2026-09-24')['measurements'],[])

if __name__=='__main__': unittest.main()
