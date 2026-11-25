"""Cowlog 地図・GPSデバッグ用のローカルサーバー。

ページ（index.html）と牧場の区画（docs/daigo-boundaries.geojson）を配信し、
/api/... を Cowlog API へ中継する。閲覧用トークンはサーバー側で付け、ブラウザには渡さない。

使い方:
    COWLOG_READ_TOKEN=... python3 tools/gps-debug/serve.py --api http://127.0.0.1:8080
    → http://127.0.0.1:8790 を開く

--api を省略すると中継は無効（ファイル読み込み・USB接続・端末の現在地だけで使う）。
"""
from __future__ import annotations

import argparse
import os
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
BOUNDARIES = ROOT / "docs" / "daigo-boundaries.geojson"
# 中継してよいのは閲覧用のGETだけ。
ALLOWED = ("/v1/dashboard", "/v1/collars", "/v1/cows/")


class Handler(SimpleHTTPRequestHandler):
    api = ""
    token = ""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(HERE), **kwargs)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_GET(self):
        path = urlsplit(self.path).path
        if path == "/boundaries.geojson":
            return self._file(BOUNDARIES, "application/geo+json")
        if path == "/config.json":
            body = ('{"api":%s}' % ("true" if self.api else "false")).encode()
            return self._bytes(200, body, "application/json")
        if path.startswith("/api/"):
            return self._proxy(self.path[len("/api"):])
        if path not in ("/", "/index.html"):
            return self._bytes(404, b"not found", "text/plain")
        return super().do_GET()

    def _proxy(self, target: str):
        route = urlsplit(target).path
        if not self.api:
            return self._bytes(503, b'{"error":"API not configured"}', "application/json")
        if not route.startswith(ALLOWED) or ".." in route:
            return self._bytes(403, b'{"error":"route not allowed"}', "application/json")
        request = Request(self.api.rstrip("/") + target,
                          headers={"Authorization": "Bearer " + self.token})
        try:
            with urlopen(request, timeout=20) as response:
                return self._bytes(response.status, response.read(), "application/json")
        except HTTPError as exc:
            return self._bytes(exc.code, exc.read() or b"{}", "application/json")
        except (URLError, TimeoutError, OSError) as exc:
            message = ('{"error":"%s"}' % str(exc).replace('"', "'")).encode()
            return self._bytes(502, message, "application/json")

    def _file(self, path: Path, kind: str):
        if not path.exists():
            return self._bytes(404, b"{}", kind)
        return self._bytes(200, path.read_bytes(), kind)

    def _bytes(self, status: int, body: bytes, kind: str):
        self.send_response(status)
        self.send_header("Content-Type", kind + ("; charset=utf-8" if "json" in kind or "text" in kind else ""))
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        # トークンや位置情報をログに残さない。
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--api", default=os.environ.get("COWLOG_API_URL", ""),
                        help="Cowlog API のURL（例 http://127.0.0.1:8080）")
    parser.add_argument("--port", type=int, default=8790)
    parser.add_argument("--host", default="127.0.0.1")
    args = parser.parse_args()
    Handler.api = args.api
    Handler.token = os.environ.get("COWLOG_READ_TOKEN", "")
    if args.api and not Handler.token:
        parser.error("--api を使うときは COWLOG_READ_TOKEN を設定してください")
    print(f"http://{args.host}:{args.port} を開いてください"
          + ("" if args.api else "（API中継なし）"))
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
