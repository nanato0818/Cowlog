"""Create clearly labeled synthetic records for a local API smoke test."""

import argparse
from datetime import timedelta

from app import dashboard, ingest, init_db, iso, register_cow, utcnow


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default="demo.sqlite3")
    args = parser.parse_args()
    init_db(args.db)
    now = utcnow().replace(second=0, microsecond=0)
    for cow_number in (1, 2):
        device = f"sample-{cow_number:02d}"
        register_cow(args.db, f"sample-cow-{cow_number}",
                     f"サンプル牛 {cow_number}", device)
        pending = []
        seq = 1
        for minutes_back in range(8 * 24 * 60, 0, -15):
            measured = now - timedelta(minutes=minutes_back)
            low_now = cow_number == 1 and minutes_back <= 120
            activity = 60 if low_now else 400
            pending.append({
                "device_id": device, "stream_id": 1, "seq": seq,
                "measured_at": iso(measured),
                "received_at": iso(measured + timedelta(seconds=8)),
                "latitude": 35.0 + cow_number * 0.001 + (seq % 20) * 0.00001,
                "longitude": 139.0 + cow_number * 0.001 + (seq % 20) * 0.000015,
                "gps_accuracy_m": 15,
                "activity_seconds": activity,
                "coverage_seconds": 900,
                "interval_seconds": 900,
                "battery_percent": 75,
            })
            if len(pending) == 100:
                ingest(args.db, pending, now)
                pending = []
            seq += 1
        if pending:
            ingest(args.db, pending, now)
    result = dashboard(args.db, now)
    for cow in result["cows"]:
        print(cow["name"], cow["status"], cow["reason"])


if __name__ == "__main__":
    main()
