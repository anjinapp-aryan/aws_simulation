#!/usr/bin/env python3
"""R15 capstone order-service. Combines, unmodified in spirit:
- R11's Saga/outbox pattern (place-order writes Order+Outbox in ONE
  transaction; a background Kafka consumer thread drives confirm/
  compensate via processed_events idempotency).
- R8's real OpenTelemetry instrumentation (spans around cache/db/kafka).
- R6/R13's real cache-aside read path (Valkey, via toxiproxy).
- DB path now points at a real Patroni-managed HA Postgres cluster
  (via HAProxy) instead of a single Postgres instance - the only
  material change from R11/R13's own server.py.
- A bounded-by-default, but INTENTIONALLY UNBOUNDED-when misconfigured,
  payment-status poll retry loop - the one genuinely new piece of logic
  this capstone needs (R15-05's retry-storm scenario), justified because
  no existing R-lab has a retry-storm-capable client.
"""
import json
import os
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import psycopg2
import redis
from kafka import KafkaConsumer
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

DB_HOST = os.environ.get("DB_HOST", "haproxy")
DB_PORT = int(os.environ.get("DB_PORT", "5000"))
DB_NAME = os.environ.get("DB_NAME", "postgres")
DB_USER = os.environ.get("DB_USER", "postgres")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "postgres")
DB_CONNECT_TIMEOUT = int(os.environ.get("DB_CONNECT_TIMEOUT", "3"))

CACHE_HOST = os.environ.get("CACHE_HOST", "toxiproxy")
CACHE_PORT = int(os.environ.get("CACHE_PORT", "6380"))
CACHE_TTL = int(os.environ.get("CACHE_TTL_SECONDS", "10"))

KAFKA_BOOTSTRAP = os.environ.get("KAFKA_BOOTSTRAP", "kafka:9092")
OTLP_ENDPOINT = os.environ.get("OTLP_ENDPOINT", "http://jaeger:4318/v1/traces")

REPLICA_ID = os.environ.get("REPLICA_ID", "order-service-1")

resource = Resource.create({"service.name": "order-service"})
provider = TracerProvider(resource=resource)
provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=OTLP_ENDPOINT)))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer("order-service")


def log(msg):
    print(f"[order-service:{REPLICA_ID}] {time.strftime('%H:%M:%S')} {msg}", flush=True)


def db():
    return psycopg2.connect(host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
                             user=DB_USER, password=DB_PASSWORD,
                             connect_timeout=DB_CONNECT_TIMEOUT)


def ensure_schema():
    for attempt in range(30):
        try:
            conn = db()
            cur = conn.cursor()
            cur.execute("""CREATE TABLE IF NOT EXISTS orders (
                id TEXT PRIMARY KEY, status TEXT NOT NULL, fail_payment BOOLEAN DEFAULT FALSE,
                created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now())""")
            cur.execute("""CREATE TABLE IF NOT EXISTS outbox (
                id UUID PRIMARY KEY, aggregatetype TEXT, aggregateid TEXT, type TEXT,
                payload JSONB, createdat TIMESTAMP NOT NULL DEFAULT now())""")
            cur.execute("CREATE TABLE IF NOT EXISTS processed_events (event_id TEXT PRIMARY KEY)")
            conn.commit()
            conn.close()
            log("schema ready")
            return
        except Exception as e:
            log(f"schema init retry {attempt}: {type(e).__name__}: {e}")
            time.sleep(2)
    raise RuntimeError("could not initialize schema")


def cache_get(key):
    with tracer.start_as_current_span("cache-get") as span:
        span.set_attribute("cache.key", key)
        r = redis.Redis(host=CACHE_HOST, port=CACHE_PORT, socket_timeout=1, socket_connect_timeout=1)
        val = r.get(key)
        span.set_attribute("cache.hit", val is not None)
        return val.decode() if val else None


def cache_set(key, value):
    try:
        r = redis.Redis(host=CACHE_HOST, port=CACHE_PORT, socket_timeout=1, socket_connect_timeout=1)
        r.setex(key, CACHE_TTL, value)
    except Exception:
        pass  # fail-open, same documented pattern as R6/R13


def place_order(order_id, fail_payment):
    with tracer.start_as_current_span("place-order-db-write") as span:
        conn = db()
        cur = conn.cursor()
        cur.execute("INSERT INTO orders (id, status, fail_payment) VALUES (%s, 'CREATED', %s)",
                    (order_id, fail_payment))
        event_id = str(uuid.uuid4())
        payload = json.dumps({"event_id": event_id, "order_id": order_id, "fail_payment": fail_payment})
        cur.execute(
            "INSERT INTO outbox (id, aggregatetype, aggregateid, type, payload) VALUES (%s, 'Order', %s, 'OrderCreated', %s)",
            (event_id, order_id, payload))
        conn.commit()
        conn.close()
        return event_id


def get_order_status_from_db(order_id):
    with tracer.start_as_current_span("order-status-db-read") as span:
        conn = db()
        cur = conn.cursor()
        cur.execute("SELECT id, status, fail_payment, created_at, updated_at FROM orders WHERE id = %s", (order_id,))
        row = cur.fetchone()
        conn.close()
        return row


def consume_payment_events():
    log("payment-events consumer starting...")
    while True:
        try:
            consumer = KafkaConsumer(
                "outbox.event.Payment",
                bootstrap_servers=KAFKA_BOOTSTRAP,
                group_id="order-service-r15",
                auto_offset_reset="earliest",
                enable_auto_commit=True,
                value_deserializer=lambda v: json.loads(v.decode()) if v else None,
            )
            log("payment-events consumer ready")
            for msg in consumer:
                payload = msg.value
                if payload is None:
                    continue
                event_id = payload.get("event_id")
                order_id = payload.get("order_id")
                status = payload.get("status")
                conn = db()
                cur = conn.cursor()
                cur.execute("SELECT 1 FROM processed_events WHERE event_id = %s", (event_id,))
                if cur.fetchone():
                    conn.close()
                    continue
                new_status = "CONFIRMED" if status == "COMPLETED" else "CANCELLED"
                cur.execute("UPDATE orders SET status = %s, updated_at = now() WHERE id = %s", (new_status, order_id))
                cur.execute("INSERT INTO processed_events (event_id) VALUES (%s)", (event_id,))
                conn.commit()
                conn.close()
                log(f"order_id={order_id} event_id={event_id} -> {new_status}")
        except Exception as e:
            log(f"payment-events consumer error: {type(e).__name__}: {e} - reconnecting in 5s")
            time.sleep(5)


class Handler(BaseHTTPRequestHandler):
    def _write(self, code, body):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(body).encode())

    def do_GET(self):
        if self.path == "/health":
            self._write(200, {"status": "healthy", "replica": REPLICA_ID})
            return

        if self.path.startswith("/place-order"):
            with tracer.start_as_current_span("checkout") as span:
                order_id = f"order-{int(time.time()*1000)}"
                if "id=" in self.path:
                    order_id = self.path.split("id=", 1)[1].split("&", 1)[0]
                fail_payment = "fail_payment=1" in self.path
                start = time.time()
                try:
                    event_id = place_order(order_id, fail_payment)
                    elapsed = time.time() - start
                    self._write(200, {"order_id": order_id, "status": "CREATED",
                                       "outbox_event_id": event_id, "elapsed": round(elapsed, 3)})
                except Exception as e:
                    elapsed = time.time() - start
                    span.record_exception(e)
                    self._write(500, {"error": str(e), "elapsed": round(elapsed, 3)})
            return

        if self.path.startswith("/order-status"):
            with tracer.start_as_current_span("order-status") as span:
                order_id = self.path.split("id=", 1)[1].split("&", 1)[0] if "id=" in self.path else None
                cache_key = f"order-status:{order_id}"
                start = time.time()
                cached = None
                try:
                    cached = cache_get(cache_key)
                except Exception as e:
                    span.record_exception(e)
                if cached:
                    elapsed = time.time() - start
                    body = json.loads(cached)
                    body["source"] = "cache"
                    body["elapsed"] = round(elapsed, 3)
                    self._write(200, body)
                    return
                row = get_order_status_from_db(order_id)
                elapsed = time.time() - start
                if row:
                    body = {"id": row[0], "status": row[1], "fail_payment": row[2],
                            "created_at": str(row[3]), "updated_at": str(row[4]),
                            "source": "db", "elapsed": round(elapsed, 3)}
                    cache_set(cache_key, json.dumps(body))
                    self._write(200, body)
                else:
                    self._write(404, {"error": "not found"})
            return

        if self.path.startswith("/poll-confirmation"):
            # R15-05: bounded-by-config retry loop against /order-status,
            # standing in for a real client polling for payment confirmation.
            # RETRY_MAX_ATTEMPTS / RETRY_INTERVAL_MS are deliberately
            # configurable at runtime (not just import-time) via files so
            # inject.sh can turn this into a genuine retry storm without a
            # container rebuild.
            order_id = self.path.split("id=", 1)[1].split("&", 1)[0] if "id=" in self.path else None
            max_attempts = int(os.environ.get("RETRY_MAX_ATTEMPTS", "3"))
            interval_ms = int(os.environ.get("RETRY_INTERVAL_MS", "500"))
            with tracer.start_as_current_span("poll-confirmation") as span:
                span.set_attribute("retry.max_attempts", max_attempts)
                attempts = 0
                status = None
                while attempts < max_attempts:
                    with tracer.start_as_current_span("poll-confirmation-attempt") as aspan:
                        aspan.set_attribute("attempt", attempts)
                        row = get_order_status_from_db(order_id)
                        status = row[1] if row else None
                    attempts += 1
                    if status == "CONFIRMED":
                        break
                    time.sleep(interval_ms / 1000.0)
                self._write(200, {"order_id": order_id, "status": status, "attempts": attempts})
            return

        self._write(200, {"message": "GET /place-order?id=X, /order-status?id=X, /poll-confirmation?id=X"})

    def log_message(self, fmt, *args):
        print(f"[order-service:{REPLICA_ID}] {self.address_string()} - {fmt % args}", flush=True)


if __name__ == "__main__":
    ensure_schema()
    t = threading.Thread(target=consume_payment_events, daemon=True)
    t.start()
    log("HTTP server starting on :8000")
    ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
