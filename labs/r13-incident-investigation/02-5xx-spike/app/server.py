#!/usr/bin/env python3
"""R9 app - extends the R4 minimal-server pattern with a real circuit
breaker (pybreaker, official-recommended Python circuit-breaker library,
not a custom implementation). Two DB-calling endpoints are exposed so
the app-level breaker and Envoy's infra-level outlier detection can be
tested independently:

  /order      - wrapped in the real pybreaker CircuitBreaker. After
                fail_max consecutive failures it opens and subsequent
                calls fail instantly (CircuitBreakerError) without even
                attempting a DB connection.
  /order-raw  - identical DB call, NOT wrapped - always attempts the
                real DB connection, used to demonstrate Envoy's own
                outlier detection in isolation and the "no protection"
                baseline.
  /breaker-status - exposes pybreaker's real current_state/fail_counter.
  /health     - always fast, never touches the DB or the breaker, used
                to prove the app stays responsive under a dependency
                outage.
"""
import json
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import psycopg2
import pybreaker

DB_HOST = os.environ.get("DB_HOST", "toxiproxy")
DB_PORT = int(os.environ.get("DB_PORT", "6432"))
DB_NAME = os.environ.get("DB_NAME", "appdb")
DB_USER = os.environ.get("DB_USER", "appuser")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "apppass")
DB_CONNECT_TIMEOUT = int(os.environ.get("DB_CONNECT_TIMEOUT", "3"))

FAIL_MAX = int(os.environ.get("BREAKER_FAIL_MAX", "3"))
RESET_TIMEOUT = int(os.environ.get("BREAKER_RESET_TIMEOUT", "10"))

db_breaker = pybreaker.CircuitBreaker(fail_max=FAIL_MAX, reset_timeout=RESET_TIMEOUT)


def db_query(order_id):
    conn = psycopg2.connect(host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
                             user=DB_USER, password=DB_PASSWORD,
                             connect_timeout=DB_CONNECT_TIMEOUT)
    cur = conn.cursor()
    cur.execute("SELECT pg_sleep(0.02), now();")
    row = cur.fetchone()
    conn.close()
    return f"order-{order_id} computed_at={row[1]}"


class Handler(BaseHTTPRequestHandler):
    def _write(self, code, body):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(body).encode())

    def do_GET(self):
        if self.path == "/health":
            self._write(200, {"status": "healthy"})
            return

        if self.path == "/breaker-status":
            self._write(200, {
                "state": str(db_breaker.current_state),
                "fail_counter": db_breaker.fail_counter,
                "fail_max": FAIL_MAX,
                "reset_timeout": RESET_TIMEOUT,
            })
            return

        order_id = "1"
        if "id=" in self.path:
            order_id = self.path.split("id=", 1)[1].split("&", 1)[0]

        if self.path.startswith("/order-raw"):
            start = time.time()
            try:
                value = db_query(order_id)
                elapsed = time.time() - start
                self._write(200, {"order_id": order_id, "value": value, "protected": False, "elapsed": round(elapsed, 3)})
            except Exception as e:
                elapsed = time.time() - start
                self._write(500, {"error": str(e), "protected": False, "elapsed": round(elapsed, 3)})
            return

        if self.path.startswith("/order"):
            start = time.time()
            try:
                value = db_breaker.call(db_query, order_id)
                elapsed = time.time() - start
                self._write(200, {"order_id": order_id, "value": value, "protected": True,
                                   "breaker_state": str(db_breaker.current_state), "elapsed": round(elapsed, 3)})
            except pybreaker.CircuitBreakerError as e:
                elapsed = time.time() - start
                self._write(503, {"error": "circuit_open", "detail": str(e), "protected": True,
                                   "breaker_state": str(db_breaker.current_state), "elapsed": round(elapsed, 3)})
            except Exception as e:
                elapsed = time.time() - start
                self._write(500, {"error": str(e), "protected": True,
                                   "breaker_state": str(db_breaker.current_state), "elapsed": round(elapsed, 3)})
            return

        self._write(200, {"message": "GET /order?id=1 (breaker-protected) or /order-raw?id=1 (unprotected)"})

    def log_message(self, fmt, *args):
        print(f"[app] {self.address_string()} - {fmt % args}", flush=True)


class LoggingListener(pybreaker.CircuitBreakerListener):
    def state_change(self, cb, old_state, new_state):
        print(f"[breaker] {time.strftime('%H:%M:%S')} state change: {old_state.name} -> {new_state.name}", flush=True)

    def failure(self, cb, exc):
        print(f"[breaker] {time.strftime('%H:%M:%S')} failure recorded ({cb.fail_counter}/{FAIL_MAX}): {type(exc).__name__}: {exc}", flush=True)


db_breaker.add_listener(LoggingListener())


if __name__ == "__main__":
    print(f"[app] starting, breaker fail_max={FAIL_MAX} reset_timeout={RESET_TIMEOUT}s", flush=True)
    ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
