"""Small HTTP API for the Cowlog iOS prototype (Python 3.11+, stdlib only)."""

from __future__ import annotations

import argparse
import hmac
import json
import os
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

JST = timezone(timedelta(hours=9))
MAX_BODY = 128_000


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def iso(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def parse_time(value: str) -> datetime:
    if not isinstance(value, str):
        raise ValueError("timestamp must be a string")
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("timestamp needs a timezone")
    return parsed.astimezone(timezone.utc)


def connect(path: str) -> sqlite3.Connection:
    db = sqlite3.connect(path, timeout=10)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA foreign_keys=ON")
    db.execute("PRAGMA journal_mode=WAL")
    return db


@contextmanager
def open_db(path: str):
    db = connect(path)
    try:
        with db:
            yield db
    finally:
        db.close()


def init_db(path: str) -> None:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with open_db(path) as db:
        db.executescript("""
            CREATE TABLE IF NOT EXISTS cows (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                device_id TEXT NOT NULL UNIQUE
            );
            CREATE TABLE IF NOT EXISTS measurements (
                device_id TEXT NOT NULL,
                stream_id INTEGER NOT NULL,
                seq INTEGER NOT NULL,
                measured_at TEXT NOT NULL,
                received_at TEXT,
                ingested_at TEXT NOT NULL,
                latitude REAL,
                longitude REAL,
                gps_accuracy_m REAL,
                activity_seconds INTEGER NOT NULL,
                coverage_seconds INTEGER NOT NULL,
                interval_seconds INTEGER NOT NULL,
                battery_percent INTEGER,
                PRIMARY KEY (device_id, stream_id, seq)
            );
            CREATE INDEX IF NOT EXISTS measurements_time
                ON measurements(device_id, measured_at);
        """)


def register_cow(path: str, cow_id: str, name: str, device_id: str) -> None:
    with open_db(path) as db:
        db.execute("""
            INSERT INTO cows(id, name, device_id) VALUES (?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET name=excluded.name, device_id=excluded.device_id
        """, (cow_id, name, device_id))


def normalized_record(raw: dict, now: datetime) -> tuple:
    if not isinstance(raw, dict):
        raise ValueError("each record must be an object")
    device = raw.get("device_id")
    if not isinstance(device, str) or not 1 <= len(device) <= 64:
        raise ValueError("invalid device_id")
    stream = raw.get("stream_id")
    seq = raw.get("seq")
    if type(stream) is not int or not 0 <= stream <= 2**32 - 1:
        raise ValueError("invalid stream_id")
    if type(seq) is not int or not 0 <= seq <= 2**32 - 1:
        raise ValueError("invalid seq")
    measured = parse_time(raw.get("measured_at"))
    if measured > now + timedelta(minutes=5):
        raise ValueError("measurement is in the future")
    received = raw.get("received_at")
    received = iso(parse_time(received)) if received is not None else None
    lat, lon = raw.get("latitude"), raw.get("longitude")
    if (lat is None) != (lon is None):
        raise ValueError("latitude and longitude must both be present or absent")
    if lat is not None:
        if type(lat) not in (int, float) or type(lon) not in (int, float):
            raise ValueError("invalid coordinates")
        if not (-90 <= lat <= 90 and -180 <= lon <= 180):
            raise ValueError("coordinates out of range")
    accuracy = raw.get("gps_accuracy_m")
    if accuracy is not None and (lat is None or type(accuracy) not in (int, float)
                                 or not 0 <= accuracy <= 10_000):
        raise ValueError("invalid gps_accuracy_m")
    interval = raw.get("interval_seconds")
    active = raw.get("activity_seconds")
    coverage = raw.get("coverage_seconds")
    if type(interval) is not int or not 1 <= interval <= 3600:
        raise ValueError("invalid interval_seconds")
    if (type(active) is not int or type(coverage) is not int
            or not 0 <= active <= coverage <= interval):
        raise ValueError("invalid activity or coverage")
    battery = raw.get("battery_percent")
    if battery is not None and (type(battery) is not int or not 0 <= battery <= 100):
        raise ValueError("invalid battery_percent")
    return (device, stream, seq, iso(measured), received, iso(now), lat, lon,
            accuracy, active, coverage, interval, battery)


def ingest(path: str, raw_records: list, now: datetime | None = None) -> dict:
    now = now or utcnow()
    if not isinstance(raw_records, list) or not 1 <= len(raw_records) <= 100:
        raise ValueError("records must contain 1 to 100 items")
    records = [normalized_record(item, now) for item in raw_records]
    accepted = 0
    with open_db(path) as db:
        for record in records:
            if db.execute("""
                INSERT INTO measurements VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(device_id, stream_id, seq) DO NOTHING
            """, record).rowcount:
                accepted += 1
    return {"accepted": accepted, "duplicates": len(records) - accepted}


def rows_for_device(db: sqlite3.Connection, device_id: str, since: datetime) -> list[dict]:
    rows = db.execute("""
        SELECT * FROM measurements WHERE device_id=? AND measured_at>=?
        ORDER BY measured_at ASC, stream_id ASC, seq ASC
    """, (device_id, iso(since))).fetchall()
    return [dict(row) for row in rows]


def activity_ratio(rows: list[dict], start: datetime, end: datetime) -> tuple[float, int] | None:
    selected = [r for r in rows if start < parse_time(r["measured_at"]) <= end]
    covered = sum(r["coverage_seconds"] for r in selected)
    if covered < 0.7 * (end - start).total_seconds():
        return None
    return sum(r["activity_seconds"] for r in selected) / covered, covered


def classify(rows: list[dict], now: datetime) -> tuple[str, str, float | None]:
    if not rows:
        return "no_data", "測定データがありません", None
    latest = max(rows, key=lambda r: r["measured_at"])
    if parse_time(latest["measured_at"]) < now - timedelta(minutes=45):
        return "disconnected", "最新データが45分以上前です", None
    recent = activity_ratio(rows, now - timedelta(hours=2), now)
    if recent is None:
        return "insufficient", "直近2時間の測定量が不足しています", None
    recent_ratio, _ = recent
    if recent_ratio <= 0.01:
        return "check", "直近2時間、動きがほとんどありません", recent_ratio
    baselines = []
    for days_back in range(1, 8):
        end = now - timedelta(days=days_back)
        result = activity_ratio(rows, end - timedelta(hours=2), end)
        if result is not None:
            baselines.append(result[0])
    if len(baselines) < 3:
        return "learning", "普段の行動量を記録中です", recent_ratio
    baselines.sort()
    baseline = baselines[len(baselines) // 2]
    if baseline - recent_ratio >= 0.10 and recent_ratio < 0.5 * baseline:
        return "check", "普段の同じ時間帯より行動量が低下しています", recent_ratio
    return "normal", "行動量に大きな低下はありません", recent_ratio


def dashboard(path: str, now: datetime | None = None) -> dict:
    now = now or utcnow()
    output = []
    with open_db(path) as db:
        for cow in db.execute("SELECT * FROM cows ORDER BY name").fetchall():
            rows = rows_for_device(db, cow["device_id"], now - timedelta(days=8))
            status, reason, ratio = classify(rows, now)
            latest = max(rows, key=lambda r: r["measured_at"]) if rows else None
            fixes = [r for r in rows if r["latitude"] is not None
                     and (r["gps_accuracy_m"] is None or r["gps_accuracy_m"] <= 100)]
            fix = max(fixes, key=lambda r: r["measured_at"]) if fixes else None
            output.append({
                "id": cow["id"], "name": cow["name"], "device_id": cow["device_id"],
                "status": status, "reason": reason,
                "latest_measured_at": latest["measured_at"] if latest else None,
                "battery_percent": latest["battery_percent"] if latest else None,
                "activity_ratio": round(ratio, 3) if ratio is not None else None,
                "latest_position": ({"latitude": fix["latitude"], "longitude": fix["longitude"],
                                     "measured_at": fix["measured_at"],
                                     "accuracy_m": fix["gps_accuracy_m"]} if fix else None),
            })
    priority = {"check": 0, "disconnected": 1, "insufficient": 2,
                "no_data": 2, "learning": 3, "normal": 4}
    output.sort(key=lambda c: (priority[c["status"]], c["name"]))
    return {"generated_at": iso(now), "cows": output}


def history(path: str, cow_id: str, day: str) -> dict | None:
    try:
        local_day = datetime.strptime(day, "%Y-%m-%d").replace(tzinfo=JST)
    except ValueError as exc:
        raise ValueError("date must be YYYY-MM-DD") from exc
    start = local_day.astimezone(timezone.utc)
    end = (local_day + timedelta(days=1)).astimezone(timezone.utc)
    with open_db(path) as db:
        cow = db.execute("SELECT * FROM cows WHERE id=?", (cow_id,)).fetchone()
        if cow is None:
            return None
        rows = [dict(r) for r in db.execute("""
            SELECT measured_at, latitude, longitude, gps_accuracy_m,
                   activity_seconds, coverage_seconds, interval_seconds
            FROM measurements WHERE device_id=? AND measured_at>=? AND measured_at<?
            ORDER BY measured_at, stream_id, seq
        """, (cow["device_id"], iso(start), iso(end))).fetchall()]
    return {"cow_id": cow_id, "date": day, "measurements": rows}


class Handler(BaseHTTPRequestHandler):
    db_path = "cowlog.sqlite3"
    read_token = ""
    ingest_token = ""

    def reply(self, status: int, payload: dict) -> None:
        encoded = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(encoded)

    def authorized(self, token: str) -> bool:
        header = self.headers.get("Authorization", "")
        return bool(token) and hmac.compare_digest(header, "Bearer " + token)

    def do_GET(self) -> None:
        if not self.authorized(self.read_token):
            self.reply(401, {"error": "unauthorized"})
            return
        route = urlparse(self.path)
        try:
            if route.path == "/v1/dashboard":
                self.reply(200, dashboard(self.db_path))
                return
            parts = route.path.strip("/").split("/")
            if len(parts) == 4 and parts[:2] == ["v1", "cows"] and parts[3] == "history":
                query = parse_qs(route.query)
                result = history(self.db_path, parts[2], query.get("date", [""])[0])
                self.reply(200 if result else 404, result or {"error": "cow not found"})
                return
            self.reply(404, {"error": "not found"})
        except ValueError as exc:
            self.reply(400, {"error": str(exc)})

    def do_POST(self) -> None:
        if self.path != "/v1/measurements":
            self.reply(404, {"error": "not found"})
            return
        if not self.authorized(self.ingest_token):
            self.reply(401, {"error": "unauthorized"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= MAX_BODY:
                raise ValueError("invalid body size")
            body = json.loads(self.rfile.read(length))
            self.reply(200, ingest(self.db_path, body.get("records")))
        except (ValueError, json.JSONDecodeError, AttributeError) as exc:
            self.reply(400, {"error": str(exc)})


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["init", "add-cow", "serve"])
    parser.add_argument("--db", default=os.environ.get("COWLOG_DB", "cowlog.sqlite3"))
    parser.add_argument("--id")
    parser.add_argument("--name")
    parser.add_argument("--device")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    args = parser.parse_args()
    init_db(args.db)
    if args.command == "add-cow":
        if not all([args.id, args.name, args.device]):
            parser.error("add-cow needs --id, --name and --device")
        register_cow(args.db, args.id, args.name, args.device)
    elif args.command == "serve":
        Handler.db_path = args.db
        Handler.read_token = os.environ.get("COWLOG_READ_TOKEN", "")
        Handler.ingest_token = os.environ.get("COWLOG_INGEST_TOKEN", "")
        if not Handler.read_token or not Handler.ingest_token:
            parser.error("set COWLOG_READ_TOKEN and COWLOG_INGEST_TOKEN")
        ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
