#!/usr/bin/env python3
"""R6 app = R4/R5's server.py pattern + one new endpoint, /cached-item,
implementing the real cache-aside pattern (check Valkey -> on miss, query
Postgres -> populate Valkey with a TTL -> return). No caching library or
framework of our own - Valkey (the real cache, via redis-py, same wire
protocol) IS the thing being tested. Postgres query intentionally does
`pg_sleep(0.1)` to simulate a moderately expensive read, so a cache hit
vs miss is visibly, measurably different - required for the R6-05
stampede experiment to actually demonstrate a DB load spike rather than
assert one.
"""
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import psycopg2
import redis

DB_HOST = os.environ.get("DB_HOST", "pgbouncer")
DB_PORT = int(os.environ.get("DB_PORT", "6432"))
DB_NAME = os.environ.get("DB_NAME", "appdb")
DB_USER = os.environ.get("DB_USER", "appuser")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "apppass")
DB_CONNECT_TIMEOUT = int(os.environ.get("DB_CONNECT_TIMEOUT", "3"))

CACHE_HOST = os.environ.get("CACHE_HOST", "valkey-proxy")
CACHE_PORT = int(os.environ.get("CACHE_PORT", "6379"))
CACHE_TIMEOUT = float(os.environ.get("CACHE_TIMEOUT", "1"))
CACHE_TTL_SECONDS = int(os.environ.get("CACHE_TTL_SECONDS", "15"))
UNHEALTHY_FLAG = "/tmp/unhealthy"


def get_from_db(item_id):
    conn = psycopg2.connect(
        host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
        user=DB_USER, password=DB_PASSWORD,
        connect_timeout=DB_CONNECT_TIMEOUT,
    )
    cur = conn.cursor()
    cur.execute("SELECT pg_sleep(0.1), now();")
    row = cur.fetchone()
    conn.close()
    return f"item-{item_id} computed_at={row[1]}"


class Handler(BaseHTTPRequestHandler):
    def _write(self, code, body):
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(body.encode())

    def do_GET(self):
        if self.path == "/health":
            if os.path.exists(UNHEALTHY_FLAG):
                self._write(500, "UNHEALTHY\n")
            else:
                self._write(200, "healthy\n")
            return

        if not self.path.startswith("/cached-item"):
            self._write(200, "Hello - GET /cached-item?id=1 to test the cache-aside path\n")
            return

        item_id = "1"
        if "id=" in self.path:
            item_id = self.path.split("id=", 1)[1].split("&", 1)[0]

        key = f"item:{item_id}"
        start = time.time()
        try:
            r = redis.Redis(host=CACHE_HOST, port=CACHE_PORT,
                             socket_timeout=CACHE_TIMEOUT,
                             socket_connect_timeout=CACHE_TIMEOUT)
            cached = r.get(key)
            if cached is not None:
                elapsed = time.time() - start
                self._write(200, f"HIT source=cache value={cached.decode()} elapsed={elapsed:.3f}s\n")
                return
        except Exception as e:
            elapsed = time.time() - start
            # Real cache-down behavior under test: fail OPEN to the database
            # rather than failing the request - this is the intentional
            # design choice R6-03 is built to surface and question, not a
            # bug being hidden.
            try:
                value = get_from_db(item_id)
                elapsed = time.time() - start
                self._write(200, f"DEGRADED source=db (cache error: {type(e).__name__}: {e}) value={value} elapsed={elapsed:.3f}s\n")
            except Exception as e2:
                elapsed = time.time() - start
                self._write(500, f"CACHE_AND_DB_ERROR after {elapsed:.3f}s: cache={type(e).__name__}: {e} db={type(e2).__name__}: {e2}\n")
            return

        try:
            value = get_from_db(item_id)
        except Exception as e:
            elapsed = time.time() - start
            self._write(500, f"DB_ERROR after {elapsed:.3f}s: {type(e).__name__}: {e}\n")
            return

        try:
            r.setex(key, CACHE_TTL_SECONDS, value)
        except Exception:
            pass  # cache write failure shouldn't fail the request

        elapsed = time.time() - start
        self._write(200, f"MISS source=db value={value} elapsed={elapsed:.3f}s\n")

    def log_message(self, fmt, *args):
        print(f"[app] {self.address_string()} - {fmt % args}")


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
