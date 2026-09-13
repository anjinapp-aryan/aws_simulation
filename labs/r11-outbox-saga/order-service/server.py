#!/usr/bin/env python3
"""Order Service - the Saga initiator/coordinator.

/place-order writes the Order row AND the Outbox row in ONE local Postgres
transaction (real atomicity) - this is the entire solution to the dual-write
problem: we never talk to Kafka directly from the request path. Debezium
(real CDC) picks the outbox row up from the WAL and relays it to Kafka.

A background thread consumes outbox.event.Payment (real Kafka consumer,
kafka-python) and drives the Saga's second half: PaymentCompleted -> confirm
the order; PaymentFailed -> COMPENSATE by cancelling it. Idempotency is
enforced via a processed_events table (same pattern proven in R7), keyed by
the outbox event's own UUID - not the Kafka offset - so genuine
redeliveries are provably deduplicated, not just assumed to be.
"""
import json
import os
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import psycopg2
from kafka import KafkaConsumer

DB_HOST = os.environ.get("DB_HOST", "order-db")
DB_NAME = os.environ.get("DB_NAME", "orderdb")
DB_USER = os.environ.get("DB_USER", "appuser")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "apppass")
KAFKA_BOOTSTRAP = os.environ.get("KAFKA_BOOTSTRAP", "kafka:9092")


def db():
    return psycopg2.connect(host=DB_HOST, dbname=DB_NAME, user=DB_USER, password=DB_PASSWORD)


def log(msg):
    print(f"[order-service] {time.strftime('%H:%M:%S')} {msg}", flush=True)


def place_order(order_id, fail_payment):
    """The atomic transaction that solves the dual-write problem."""
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


def consume_payment_events():
    log("payment-events consumer starting...")
    consumer = KafkaConsumer(
        "outbox.event.Payment",
        bootstrap_servers=KAFKA_BOOTSTRAP,
        group_id="order-service-v2",
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
            log(f"DUPLICATE event_id={event_id} order_id={order_id} status={status} - already processed, SKIPPING (idempotency)")
            conn.close()
            continue
        new_status = "CONFIRMED" if status == "COMPLETED" else "CANCELLED"
        cur.execute("UPDATE orders SET status = %s, updated_at = now() WHERE id = %s", (new_status, order_id))
        cur.execute("INSERT INTO processed_events (event_id) VALUES (%s)", (event_id,))
        conn.commit()
        conn.close()
        verb = "CONFIRMED" if new_status == "CONFIRMED" else "COMPENSATED (cancelled)"
        log(f"order_id={order_id} event_id={event_id} payment_status={status} -> order {verb}")


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
        if self.path.startswith("/place-order"):
            order_id = f"order-{int(time.time()*1000)}"
            if "id=" in self.path:
                order_id = self.path.split("id=", 1)[1].split("&", 1)[0]
            fail_payment = "fail_payment=1" in self.path or "fail_payment=true" in self.path
            event_id = place_order(order_id, fail_payment)
            self._write(200, {"order_id": order_id, "status": "CREATED", "outbox_event_id": event_id, "fail_payment": fail_payment})
            return
        if self.path.startswith("/order-status"):
            order_id = self.path.split("id=", 1)[1].split("&", 1)[0] if "id=" in self.path else None
            conn = db()
            cur = conn.cursor()
            cur.execute("SELECT id, status, fail_payment, created_at, updated_at FROM orders WHERE id = %s", (order_id,))
            row = cur.fetchone()
            conn.close()
            if row:
                self._write(200, {"id": row[0], "status": row[1], "fail_payment": row[2],
                                   "created_at": str(row[3]), "updated_at": str(row[4])})
            else:
                self._write(404, {"error": "not found"})
            return
        self._write(200, {"message": "GET /place-order?id=X&fail_payment=0|1, /order-status?id=X"})

    def log_message(self, fmt, *args):
        print(f"[order-service] {self.address_string()} - {fmt % args}", flush=True)


if __name__ == "__main__":
    t = threading.Thread(target=consume_payment_events, daemon=True)
    t.start()
    log("HTTP server starting on :8000")
    ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
