#!/usr/bin/env python3
"""R14 app - R4's exact minimal-server pattern, pointed at Patroni's
HAProxy endpoint (port 5000 = always the current leader, real Patroni
health-check routing) instead of a single Postgres host. Adds /write and
/read against a real table so R14's HA/failover/RPO experiments have
real, tagged, timestamped data to check for survival across a failover
or restore - not just a health check.
"""
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import psycopg2

DB_HOST = os.environ.get("DB_HOST", "haproxy")
DB_PORT = int(os.environ.get("DB_PORT", "5000"))
DB_NAME = os.environ.get("DB_NAME", "postgres")
DB_USER = os.environ.get("DB_USER", "postgres")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "postgres")
DB_CONNECT_TIMEOUT = int(os.environ.get("DB_CONNECT_TIMEOUT", "3"))
REPLICA_PORT = int(os.environ.get("REPLICA_PORT", "5001"))


def connect(port=None):
    return psycopg2.connect(host=DB_HOST, port=port or DB_PORT, dbname=DB_NAME,
                             user=DB_USER, password=DB_PASSWORD,
                             connect_timeout=DB_CONNECT_TIMEOUT)


def ensure_table(cur):
    cur.execute("CREATE TABLE IF NOT EXISTS r14_events (id SERIAL PRIMARY KEY, tag TEXT, written_at TIMESTAMPTZ DEFAULT now())")


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

        start = time.time()
        try:
            if self.path.startswith("/write"):
                tag = "auto"
                if "tag=" in self.path:
                    tag = self.path.split("tag=", 1)[1].split("&", 1)[0]
                conn = connect()
                cur = conn.cursor()
                ensure_table(cur)
                cur.execute("INSERT INTO r14_events (tag) VALUES (%s) RETURNING id, written_at", (tag,))
                row = cur.fetchone()
                conn.commit()
                pid = conn.get_backend_pid()
                conn.close()
                elapsed = time.time() - start
                self._write(200, f"WROTE id={row[0]} tag={tag} written_at={row[1]} backend_pid={pid} elapsed={elapsed:.3f}s\n")
                return

            if self.path.startswith("/read-replica"):
                conn = connect(port=REPLICA_PORT)
                cur = conn.cursor()
                cur.execute("SELECT max(id), pg_is_in_recovery() FROM r14_events")
                max_id, in_recovery = cur.fetchone()
                conn.close()
                elapsed = time.time() - start
                self._write(200, f"replica_max_id={max_id} in_recovery={in_recovery} elapsed={elapsed:.3f}s\n")
                return

            if self.path.startswith("/read"):
                conn = connect()
                cur = conn.cursor()
                ensure_table(cur)
                cur.execute("SELECT id, tag, written_at FROM r14_events ORDER BY id DESC LIMIT 10")
                rows = cur.fetchall()
                cur.execute("SELECT pg_is_in_recovery()")
                in_recovery = cur.fetchone()[0]
                conn.close()
                elapsed = time.time() - start
                body = f"served_by_replica={in_recovery} elapsed={elapsed:.3f}s\n"
                for r in rows:
                    body += f"  id={r[0]} tag={r[1]} written_at={r[2]}\n"
                self._write(200, body)
                return

            if self.path.startswith("/whoami"):
                conn = connect()
                cur = conn.cursor()
                cur.execute("SELECT pg_is_in_recovery(), inet_server_addr()")
                recovery, addr = cur.fetchone()
                conn.close()
                elapsed = time.time() - start
                self._write(200, f"leader={not recovery} server_addr={addr} elapsed={elapsed:.3f}s\n")
                return

            self._write(200, "GET /write?tag=X, /read, /whoami, /health\n")
        except Exception as e:
            elapsed = time.time() - start
            self._write(500, f"DB_ERROR after {elapsed:.3f}s: {type(e).__name__}: {e}\n")

    def log_message(self, fmt, *args):
        print(f"[app] {self.address_string()} - {fmt % args}", flush=True)


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
