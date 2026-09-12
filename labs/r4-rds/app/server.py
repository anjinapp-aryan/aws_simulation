#!/usr/bin/env python3
"""Same minimal self-identifying HTTP server pattern used in R2/R3
(labs/R2-alb-behavior/app/server.py, labs/r3-ecs/app/server.py). The only
new addition is /db - real psycopg2 connectivity through Toxiproxy ->
PgBouncer -> Postgres. No ORM, no connection-pool library of our own
(PgBouncer IS the pool being tested) - one query per request, real
psycopg2 exceptions surfaced verbatim so failure text is genuine.
"""
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import psycopg2

DB_HOST = os.environ.get("DB_HOST", "toxiproxy")
DB_PORT = int(os.environ.get("DB_PORT", "6432"))
DB_NAME = os.environ.get("DB_NAME", "appdb")
DB_USER = os.environ.get("DB_USER", "appuser")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "apppass")
DB_CONNECT_TIMEOUT = int(os.environ.get("DB_CONNECT_TIMEOUT", "3"))


class Handler(BaseHTTPRequestHandler):
    def _write(self, code, body):
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(body.encode())

    def do_GET(self):
        if self.path == "/health":
            self._write(200, "healthy\n")
            return
        if self.path != "/db":
            self._write(200, "Hello - GET /db to test the database chain\n")
            return

        start = time.time()
        try:
            conn = psycopg2.connect(
                host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
                user=DB_USER, password=DB_PASSWORD,
                connect_timeout=DB_CONNECT_TIMEOUT,
            )
            cur = conn.cursor()
            cur.execute("SELECT now(), pg_backend_pid();")
            row = cur.fetchone()
            conn.close()
            elapsed = time.time() - start
            self._write(200, f"OK db_time={row[0]} backend_pid={row[1]} elapsed={elapsed:.3f}s\n")
        except Exception as e:
            elapsed = time.time() - start
            # Real psycopg2 exception text, unmodified - this is the actual
            # evidence a real ECS task's application logs would show.
            self._write(500, f"DB_ERROR after {elapsed:.3f}s: {type(e).__name__}: {e}\n")

    def log_message(self, fmt, *args):
        print(f"[app] {self.address_string()} - {fmt % args}")


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
