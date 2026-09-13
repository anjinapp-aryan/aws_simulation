#!/usr/bin/env python3
"""Payment Service - consumes real OrderCreated events (relayed by Debezium
via Kafka), "processes" payment (deterministic success/failure driven by the
order's fail_payment flag, so experiments are reproducible), and writes its
own Payment row + Outbox row in ONE local transaction on its OWN database -
the same dual-write-safe pattern as the Order Service, proving the outbox
pattern composes across independently-owned services.
"""
import json
import os
import time
import uuid

import psycopg2
from kafka import KafkaConsumer

DB_HOST = os.environ.get("DB_HOST", "payment-db")
DB_NAME = os.environ.get("DB_NAME", "paymentdb")
DB_USER = os.environ.get("DB_USER", "appuser")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "apppass")
KAFKA_BOOTSTRAP = os.environ.get("KAFKA_BOOTSTRAP", "kafka:9092")
CONSUMER_ID = os.environ.get("CONSUMER_ID", "payment-1")


def db():
    return psycopg2.connect(host=DB_HOST, dbname=DB_NAME, user=DB_USER, password=DB_PASSWORD)


def log(msg):
    print(f"[{CONSUMER_ID}] {time.strftime('%H:%M:%S')} {msg}", flush=True)


def main():
    log("order-events consumer starting...")
    consumer = KafkaConsumer(
        "outbox.event.Order",
        bootstrap_servers=KAFKA_BOOTSTRAP,
        group_id="payment-service-v2",
        auto_offset_reset="earliest",
        enable_auto_commit=True,
        value_deserializer=lambda v: json.loads(v.decode()) if v else None,
    )
    log("order-events consumer ready")
    for msg in consumer:
        payload = msg.value
        if payload is None:
            continue
        order_event_id = payload.get("event_id")
        order_id = payload.get("order_id")
        fail_payment = payload.get("fail_payment", False)

        conn = db()
        cur = conn.cursor()
        cur.execute("SELECT 1 FROM processed_events WHERE event_id = %s", (order_event_id,))
        if cur.fetchone():
            log(f"DUPLICATE order_event_id={order_event_id} order_id={order_id} - already processed, SKIPPING (idempotency)")
            conn.close()
            continue

        status = "FAILED" if fail_payment else "COMPLETED"
        payment_id = f"pay-{order_id}"
        log(f"order_id={order_id} fail_payment={fail_payment} -> processing payment, result={status}")

        cur.execute("INSERT INTO payments (id, order_id, status) VALUES (%s, %s, %s) "
                    "ON CONFLICT (id) DO NOTHING", (payment_id, order_id, status))
        payment_event_id = str(uuid.uuid4())
        out_payload = json.dumps({"event_id": payment_event_id, "order_id": order_id, "status": status})
        cur.execute(
            "INSERT INTO outbox (id, aggregatetype, aggregateid, type, payload) VALUES (%s, 'Payment', %s, %s, %s)",
            (payment_event_id, order_id, "PaymentCompleted" if status == "COMPLETED" else "PaymentFailed", out_payload))
        cur.execute("INSERT INTO processed_events (event_id) VALUES (%s)", (order_event_id,))
        conn.commit()
        conn.close()
        log(f"order_id={order_id} payment {status}, outbox event {payment_event_id} written (real local transaction)")


if __name__ == "__main__":
    main()
