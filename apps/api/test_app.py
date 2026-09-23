import tempfile
import json
import threading
import unittest
from datetime import datetime, timedelta, timezone
from http.server import ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from app import Handler, dashboard, history, ingest, init_db, register_cow


NOW = datetime(2026, 9, 24, 12, 0, tzinfo=timezone.utc)


def record(seq, at, active=400, coverage=900, lat=35.0):
    return {
        "device_id": "collar-01", "stream_id": 7, "seq": seq,
        "measured_at": at.isoformat(), "latitude": lat, "longitude": 139.0,
        "gps_accuracy_m": 12, "activity_seconds": active,
        "coverage_seconds": coverage, "interval_seconds": 900,
        "battery_percent": 80,
    }


class ApiDataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.db = str(Path(self.temp.name) / "test.sqlite3")
        init_db(self.db)
        register_cow(self.db, "cow-01", "うし1", "collar-01")

    def tearDown(self):
        self.temp.cleanup()

    def test_deduplicates_backfill_by_record_identity(self):
        one = record(1, NOW - timedelta(minutes=15))
        self.assertEqual(ingest(self.db, [one], NOW), {"accepted": 1, "duplicates": 0})
        self.assertEqual(ingest(self.db, [one], NOW), {"accepted": 0, "duplicates": 1})
        self.assertEqual(len(history(self.db, "cow-01", "2026-09-24")["measurements"]), 1)

    def test_missing_coverage_is_not_inactivity(self):
        ingest(self.db, [record(1, NOW - timedelta(minutes=15), 0, 100)], NOW)
        self.assertEqual(dashboard(self.db, NOW)["cows"][0]["status"], "insufficient")

    def test_two_hours_of_stillness_needs_check(self):
        readings = [record(n, NOW - timedelta(minutes=15 * (8 - n)), 0)
                    for n in range(1, 9)]
        ingest(self.db, readings, NOW)
        self.assertEqual(dashboard(self.db, NOW)["cows"][0]["status"], "check")

    def test_stale_data_is_device_issue(self):
        ingest(self.db, [record(1, NOW - timedelta(hours=2))], NOW)
        self.assertEqual(dashboard(self.db, NOW)["cows"][0]["status"], "disconnected")

    def test_gps_can_be_absent_while_activity_is_present(self):
        readings = []
        for seq in range(1, 9):
            item = record(seq, NOW - timedelta(minutes=15 * (8 - seq)), 300, lat=None)
            item["longitude"] = None
            item["gps_accuracy_m"] = None
            readings.append(item)
        ingest(self.db, readings, NOW)
        cow = dashboard(self.db, NOW)["cows"][0]
        self.assertIsNone(cow["latest_position"])
        self.assertEqual(cow["status"], "learning")

    def test_low_activity_against_baseline(self):
        readings = []
        seq = 1
        for days_back in (3, 2, 1, 0):
            for interval in range(8):
                at = NOW - timedelta(days=days_back, minutes=15 * (7 - interval))
                readings.append(record(seq, at, 450 if days_back else 100))
                seq += 1
        ingest(self.db, readings, NOW)
        cow = dashboard(self.db, NOW)["cows"][0]
        self.assertEqual(cow["status"], "check")
        self.assertIn("行動量", cow["reason"])

    def test_invalid_activity_is_rejected(self):
        bad = record(1, NOW)
        bad["activity_seconds"] = 901
        with self.assertRaises(ValueError):
            ingest(self.db, [bad], NOW)

    def test_http_ingest_and_read_require_separate_tokens(self):
        class TestHandler(Handler):
            db_path = self.db
            read_token = "read-secret"
            ingest_token = "ingest-secret"

            def log_message(self, *_args):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), TestHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        root = f"http://127.0.0.1:{server.server_port}"
        try:
            payload = json.dumps({"records": [record(1, datetime.now(timezone.utc) - timedelta(minutes=15))]}).encode()
            request = Request(root + "/v1/measurements", data=payload,
                              headers={"Authorization": "Bearer ingest-secret",
                                       "Content-Type": "application/json"})
            with urlopen(request) as response:
                self.assertEqual(json.load(response)["accepted"], 1)
            request = Request(root + "/v1/dashboard",
                              headers={"Authorization": "Bearer read-secret"})
            with urlopen(request) as response:
                self.assertEqual(json.load(response)["cows"][0]["id"], "cow-01")
            with self.assertRaises(HTTPError) as unauthorized:
                urlopen(root + "/v1/dashboard")
            self.assertEqual(unauthorized.exception.code, 401)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)


if __name__ == "__main__":
    unittest.main()
