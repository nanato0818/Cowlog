"""Small HTTP API for the Cowlog iOS prototype (Python 3.11+, stdlib only)."""

from __future__ import annotations

import argparse
import hmac
import json
import os
import sqlite3
import re
import uuid
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse, unquote

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
                device_id TEXT UNIQUE,
                herd_number TEXT,
                individual_number TEXT
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
        measurement_columns = {row["name"] for row in db.execute("PRAGMA table_info(measurements)")}
        for column, kind in (("hdop", "REAL"), ("satellites", "INTEGER")):
            if column not in measurement_columns:
                db.execute(f"ALTER TABLE measurements ADD COLUMN {column} {kind}")
        # Migrate the original registry without changing measurement identities.
        columns = {row["name"]: row for row in db.execute("PRAGMA table_info(cows)")}
        if columns["device_id"]["notnull"]:
            db.executescript("""
                BEGIN IMMEDIATE;
                ALTER TABLE cows RENAME TO cows_legacy;
                CREATE TABLE cows (id TEXT PRIMARY KEY, name TEXT NOT NULL,
                    device_id TEXT UNIQUE, herd_number TEXT, individual_number TEXT);
                INSERT INTO cows(id,name,device_id) SELECT id,name,device_id FROM cows_legacy;
                DROP TABLE cows_legacy;
                COMMIT;
            """)
        cow_columns = {row["name"] for row in db.execute("PRAGMA table_info(cows)")}
        if "cow_style" not in cow_columns:
            db.execute("ALTER TABLE cows ADD COLUMN cow_style TEXT NOT NULL DEFAULT 'unknown'")
        db.executescript("""
            CREATE TABLE IF NOT EXISTS collar_assignments (
                cow_id TEXT NOT NULL REFERENCES cows(id),
                device_id TEXT NOT NULL,
                started_at TEXT NOT NULL,
                ended_at TEXT,
                PRIMARY KEY(device_id, started_at)
            );
            CREATE INDEX IF NOT EXISTS assignments_cow_time
                ON collar_assignments(cow_id, started_at, ended_at);
            CREATE UNIQUE INDEX IF NOT EXISTS one_cow_per_collar
                ON collar_assignments(device_id) WHERE ended_at IS NULL;
            CREATE UNIQUE INDEX IF NOT EXISTS one_collar_per_cow
                ON collar_assignments(cow_id) WHERE ended_at IS NULL;
        """)
        # Legacy assignments have no known start time: preserve historical access.
        db.execute("""INSERT INTO collar_assignments(cow_id,device_id,started_at)
            SELECT id,device_id,'0001-01-01T00:00:00Z' FROM cows c
            WHERE device_id IS NOT NULL AND NOT EXISTS
                (SELECT 1 FROM collar_assignments a WHERE a.cow_id=c.id)""")


def register_cow(path: str, cow_id: str, name: str, device_id: str | None = None,
                 effective_at: datetime | None = None, herd_number: str | None = None,
                 individual_number: str | None = None) -> None:
    for label, value in (("cow id", cow_id), ("name", name)):
        if not isinstance(value, str) or not value.strip() or len(value) > 128:
            raise ValueError(f"invalid {label}")
    if device_id is not None and (not device_id.strip() or len(device_id) > 64):
        raise ValueError("invalid device_id")
    for value in (herd_number, individual_number):
        if value is not None and (not isinstance(value, str) or not value.strip() or len(value) > 128):
            raise ValueError("numbers must be non-empty strings up to 128 characters")
    # All attachment changes are serialized. The start time is mandatory in practice;
    # callers default to now, never implicitly reattribute pre-attachment records.
    at = iso(effective_at or utcnow())
    with open_db(path) as db:
        db.execute("BEGIN IMMEDIATE")
        db.execute("""INSERT INTO cows(id,name,herd_number,individual_number) VALUES (?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET name=excluded.name,
            herd_number=COALESCE(excluded.herd_number,cows.herd_number),
            individual_number=COALESCE(excluded.individual_number,cows.individual_number)
            """, (cow_id, name, herd_number, individual_number))
        current = db.execute("SELECT device_id FROM cows WHERE id=?", (cow_id,)).fetchone()[0]
        if current == device_id:
            return
        affected = db.execute("""SELECT * FROM collar_assignments
            WHERE ended_at IS NULL AND (cow_id=? OR device_id=?)""",
            (cow_id, device_id)).fetchall()
        if any(row["started_at"] >= at for row in affected):
            raise ValueError("attachment time must follow existing attachment start")
        if effective_at and effective_at > utcnow():
            raise ValueError("future attachment is not supported")
        # Reject edits to the past once a newer interval already exists.
        if db.execute("""SELECT 1 FROM collar_assignments
            WHERE (cow_id=? OR device_id=?) AND (started_at>? OR ended_at>?)""",
            (cow_id, device_id, at, at)).fetchone():
            raise ValueError("attachment time overlaps newer assignment history")
        db.execute("""UPDATE collar_assignments SET ended_at=?
            WHERE ended_at IS NULL AND (cow_id=? OR device_id=?)""", (at,cow_id,device_id))
        db.execute("UPDATE cows SET device_id=NULL WHERE id=? OR device_id=?", (cow_id,device_id))
        if device_id is not None:
            db.execute("INSERT INTO collar_assignments VALUES (?,?,?,NULL)", (cow_id,device_id,at))
            db.execute("UPDATE cows SET device_id=? WHERE id=?", (device_id,cow_id))

class NumberConflict(ValueError):
    pass


def register_collar(path: str, device: str, number: str, style: str = "unknown") -> dict:
    """Explicit server registration; does not provision hardware/cloud credentials."""
    if not isinstance(device,str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.:-]{0,63}",device):
        raise ValueError("invalid device_id")
    if not isinstance(number,str) or not re.fullmatch(r"[0-9]{1,12}",number):
        raise ValueError("number must contain 1 to 12 ASCII digits")
    if style not in ("unknown","holstein","brown"):
        raise ValueError("invalid cow style")
    result={"device_id":device,"number":number,"cow_style":style,"saved_to":"server"}
    with open_db(path) as db:
        db.execute("BEGIN IMMEDIATE")
        current=db.execute("SELECT * FROM cows WHERE device_id=?",(device,)).fetchone()
        if current:
            if current["herd_number"]==number and current["cow_style"]==style:
                return {**result,"created":False}
            raise NumberConflict("collar already registered")
        if db.execute("SELECT 1 FROM cows WHERE herd_number=?",(number,)).fetchone():
            raise NumberConflict("number already in use")
        cow_id="collar-"+uuid.uuid4().hex
        db.execute("INSERT INTO cows(id,name,device_id,herd_number,cow_style) VALUES (?,?,?,?,?)",(cow_id,number,device,number,style))
        previous=db.execute("SELECT MAX(ended_at) FROM collar_assignments WHERE device_id=?",(device,)).fetchone()[0]
        db.execute("INSERT INTO collar_assignments VALUES (?,?,?,NULL)",(cow_id,device,previous or '0001-01-01T00:00:00Z'))
    return {**result,"created":True}


def collars(path: str) -> dict:
    """Only known devices; pending devices are discovered from received records."""
    with open_db(path) as db:
        rows = db.execute("""SELECT d.device_id,c.herd_number AS number, COALESCE(c.cow_style,'unknown') AS cow_style,
            MAX(m.measured_at) AS last_seen_at FROM
            (SELECT device_id FROM measurements UNION SELECT device_id FROM cows
             WHERE device_id IS NOT NULL) d
            LEFT JOIN cows c ON c.device_id=d.device_id
            LEFT JOIN measurements m ON m.device_id=d.device_id
            GROUP BY d.device_id,c.herd_number ORDER BY d.device_id""").fetchall()
    return {"collars": [dict(row) for row in rows]}


def set_collar_number(path: str, device_id: str, number: str,
                      expected_number: str | None, cow_style: str | None = None,
                      expected_style: str | None = None) -> dict:
    # ASCII digits only: keep leading zeros and avoid ambiguous visual aliases.
    if not isinstance(number, str) or not re.fullmatch(r"[0-9]{1,12}", number):
        raise ValueError("number must contain 1 to 12 ASCII digits")
    if expected_number is not None and not isinstance(expected_number, str):
        raise ValueError("invalid expected_number")
    styles = ("unknown", "holstein", "brown")
    if cow_style is not None and (cow_style not in styles or expected_style not in styles):
        raise ValueError("invalid cow style")
    with open_db(path) as db:
        db.execute("BEGIN IMMEDIATE")
        known = db.execute("SELECT 1 FROM measurements WHERE device_id=? UNION "
                           "SELECT 1 FROM cows WHERE device_id=?", (device_id,device_id)).fetchone()
        if not known:
            raise LookupError("collar not found")
        cow = db.execute("SELECT * FROM cows WHERE device_id=?", (device_id,)).fetchone()
        current = cow["herd_number"] if cow else None
        current_style = cow["cow_style"] if cow else "unknown"
        next_style = cow_style if cow_style is not None else current_style
        result = {"device_id": device_id, "number": number, "cow_style": next_style, "saved_to": "server"}
        if current != expected_number or (cow_style is not None and current_style != expected_style):
            # A retry after an ambiguous network failure is safe and idempotent.
            if current == number and current_style == next_style:
                return result
            raise NumberConflict("number changed; reload collars before saving")
        if db.execute("SELECT 1 FROM cows WHERE herd_number=? AND "
                      "(device_id IS NULL OR device_id!=?)", (number,device_id)).fetchone():
            raise NumberConflict("number already in use")
        if cow:
            db.execute("UPDATE cows SET name=?,herd_number=?,cow_style=? WHERE id=?",
                       (number,number,next_style,cow["id"]))
        else:
            cow_id = "collar-" + uuid.uuid4().hex
            db.execute("INSERT INTO cows(id,name,device_id,herd_number,cow_style) VALUES (?,?,?,?,?)",
                       (cow_id,number,device_id,number,next_style))
            # First numbering includes received telemetry. A reused legacy collar
            # starts after its last assignment, so earlier animals keep their data.
            previous = db.execute("SELECT MAX(ended_at) FROM collar_assignments "
                                  "WHERE device_id=?", (device_id,)).fetchone()[0]
            db.execute("INSERT INTO collar_assignments VALUES (?,?,?,NULL)",
                       (cow_id,device_id,previous or '0001-01-01T00:00:00Z'))
    return result


def rows_for_cow(db: sqlite3.Connection, cow_id: str, since: datetime,
                 until: datetime | None = None) -> list[dict]:
    return [dict(row) for row in db.execute("""
        SELECT m.* FROM measurements m JOIN collar_assignments a
            ON a.device_id=m.device_id AND m.measured_at>=a.started_at
            AND (a.ended_at IS NULL OR m.measured_at<a.ended_at)
        WHERE a.cow_id=? AND m.measured_at>=? AND m.measured_at<?
        ORDER BY m.measured_at,m.stream_id,m.seq
    """, (cow_id,iso(since),iso(until) if until else '9999-12-31T23:59:59Z')).fetchall()]


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
    hdop = raw.get("hdop")
    satellites = raw.get("satellites")
    if hdop is not None and (type(hdop) not in (int,float) or not 0 <= hdop <= 100):
        raise ValueError("invalid hdop")
    if satellites is not None and (type(satellites) is not int or not 0 <= satellites <= 200):
        raise ValueError("invalid satellites")
    return (device, stream, seq, iso(measured), received, iso(now), lat, lon,
            accuracy, active, coverage, interval, battery, hdop, satellites)


def ingest(path: str, raw_records: list, now: datetime | None = None) -> dict:
    now = now or utcnow()
    if not isinstance(raw_records, list) or not 1 <= len(raw_records) <= 100:
        raise ValueError("records must contain 1 to 100 items")
    records = [normalized_record(item, now) for item in raw_records]
    accepted = 0
    with open_db(path) as db:
        for record in records:
            if db.execute("""
                INSERT INTO measurements (device_id,stream_id,seq,measured_at,received_at,
                    ingested_at,latitude,longitude,gps_accuracy_m,activity_seconds,
                    coverage_seconds,interval_seconds,battery_percent,hdop,satellites)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
            rows = rows_for_cow(db, cow["id"], now - timedelta(days=8), now + timedelta(seconds=1))
            # Current status/battery must not come from an old collar.
            # Earlier collars remain available through the animal's history API.
            active = db.execute("""SELECT * FROM collar_assignments
                WHERE cow_id=? AND ended_at IS NULL""", (cow["id"],)).fetchone()
            rows = [row for row in rows if active and row["device_id"] == active["device_id"]
                    and row["measured_at"] >= active["started_at"]]
            status, reason, ratio = classify(rows, now)
            latest = max(rows, key=lambda r: r["measured_at"]) if rows else None
            fixes = [r for r in rows if r["latitude"] is not None
                     and (r["gps_accuracy_m"] is None or r["gps_accuracy_m"] <= 100)]
            fix = max(fixes, key=lambda r: r["measured_at"]) if fixes else None
            output.append({
                "id": cow["id"], "name": cow["herd_number"] or cow["name"],
                "number": cow["herd_number"] or cow["name"], "device_id": cow["device_id"],
                "cow_style": cow["cow_style"],
                "profile": {"herd_number": cow["herd_number"] or cow["name"],
                            "individual_number": cow["individual_number"],
                            "breed": "未登録", "birth_date": "未登録"},
                "status": status, "reason": reason,
                "latest_measured_at": latest["measured_at"] if latest else None,
                "battery_percent": latest["battery_percent"] if latest else None,
                "activity_ratio": round(ratio, 3) if ratio is not None else None,
                "latest_position": ({"latitude": fix["latitude"], "longitude": fix["longitude"],
                                     "measured_at": fix["measured_at"],
                                     "accuracy_m": fix["gps_accuracy_m"],
                                     "hdop": fix["hdop"], "satellites": fix["satellites"]} if fix else None),
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
        rows = rows_for_cow(db,cow_id,start,end)

    return {"cow_id": cow_id, "date": day, "measurements": rows}


class Handler(BaseHTTPRequestHandler):
    db_path = "cowlog.sqlite3"
    read_token = ""
    ingest_token = ""
    manage_token = ""

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
            if route.path == "/v1/collars":
                self.reply(200, collars(self.db_path))
                return
            if route.path == "/v1/dashboard":
                self.reply(200, dashboard(self.db_path))
                return
            parts = route.path.strip("/").split("/")
            if len(parts) == 4 and parts[:2] == ["v1", "cows"] and parts[3] == "history":
                query = parse_qs(route.query)
                result = history(self.db_path, unquote(parts[2]), query.get("date", [""])[0])
                self.reply(200 if result else 404, result or {"error": "cow not found"})
                return
            self.reply(404, {"error": "not found"})
        except ValueError as exc:
            self.reply(400, {"error": str(exc)})

    def do_PUT(self) -> None:
        parts = urlparse(self.path).path.strip("/").split("/")
        if len(parts) != 4 or parts[:2] != ["v1", "collars"] or parts[3] != "number":
            self.reply(404, {"error": "not found"})
            return
        if not self.authorized(self.manage_token):
            self.reply(401, {"error": "number management permission required"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= MAX_BODY:
                raise ValueError("invalid body size")
            body = json.loads(self.rfile.read(length))
            if not isinstance(body, dict) or "expected_number" not in body:
                raise ValueError("expected_number is required")
            result = set_collar_number(self.db_path, unquote(parts[2]),
                                       body.get("number"), body["expected_number"],
                                       body.get("cow_style"), body.get("expected_style"))
            self.reply(200, result)
        except NumberConflict as exc:
            self.reply(409, {"error": str(exc)})
        except LookupError as exc:
            self.reply(404, {"error": str(exc)})
        except (ValueError, AttributeError) as exc:
            self.reply(400, {"error": str(exc)})

    def do_POST(self) -> None:
        path=urlparse(self.path).path
        if path not in ("/v1/measurements","/v1/collars"):
            self.reply(404,{"error":"not found"})
            return
        token=self.manage_token if path=="/v1/collars" else self.ingest_token
        if not self.authorized(token):
            self.reply(401,{"error":"unauthorized"})
            return
        try:
            length=int(self.headers.get("Content-Length","0"))
            if not 0<length<=MAX_BODY: raise ValueError("invalid body size")
            body=json.loads(self.rfile.read(length))
            if not isinstance(body,dict): raise ValueError("body must be an object")
            if path=="/v1/collars":
                result=register_collar(self.db_path,body.get("device_id"),body.get("number"),body.get("cow_style","unknown"))
                self.reply(201 if result["created"] else 200,result)
            else: self.reply(200,ingest(self.db_path,body.get("records")))
        except NumberConflict as exc: self.reply(409,{"error":str(exc)})
        except (ValueError,AttributeError) as exc: self.reply(400,{"error":str(exc)})


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["init", "add-cow", "serve"])
    parser.add_argument("--db", default=os.environ.get("COWLOG_DB", "cowlog.sqlite3"))
    parser.add_argument("--id")
    parser.add_argument("--name")
    parser.add_argument("--device", help="omit to detach the current collar")
    parser.add_argument("--herd-number")
    parser.add_argument("--individual-number")
    parser.add_argument("--effective-at", help="UTC attachment time; defaults to now")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    args = parser.parse_args()
    init_db(args.db)
    if args.command == "add-cow":
        if not all([args.id, args.name]):
            parser.error("add-cow needs --id and --name")
        try:
            register_cow(args.db, args.id, args.name, args.device,
                         parse_time(args.effective_at) if args.effective_at else None,
                         args.herd_number, args.individual_number)
        except ValueError as exc:
            parser.error(str(exc))
    elif args.command == "serve":
        Handler.db_path = args.db
        Handler.read_token = os.environ.get("COWLOG_READ_TOKEN", "")
        Handler.ingest_token = os.environ.get("COWLOG_INGEST_TOKEN", "")
        Handler.manage_token = os.environ.get("COWLOG_MANAGE_TOKEN", "")
        tokens = [t for t in (Handler.read_token, Handler.ingest_token, Handler.manage_token) if t]
        if len(set(tokens)) != len(tokens):
            parser.error("read, ingest and manage tokens must be different")
        if not Handler.read_token or not Handler.ingest_token:
            parser.error("set COWLOG_READ_TOKEN and COWLOG_INGEST_TOKEN")
        ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
