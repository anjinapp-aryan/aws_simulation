#!/usr/bin/env python3
"""R7 consumer - thin adapter around pika (the official-recommended Python
AMQP client), not a custom broker/queue/DLQ/retry engine. All retry-delay,
DLQ, and redelivery behavior below is implemented using REAL RabbitMQ
mechanisms: real queues, real per-queue message TTL (x-message-ttl) for
timed backoff, real dead-lettering, and real unacked-message requeue on a
dropped connection (used for the duplicate-delivery experiments).

Message types (routed by the 'type' field in the JSON body):
  normal            - process and ack.
  poison            - always fails; explicitly routed through
                       orders-retry-1/2/3 (real TTL-delay queues) then to
                       orders-dlq after 3 attempts. Attempt count is
                       carried in a message header we set ourselves
                       (x-retry-attempt) - simple and auditable.
  crash             - writes a side-effect log entry, THEN hard-exits
                       BEFORE acking, so RabbitMQ (a real broker) detects
                       the dropped connection and redelivers the message
                       to whichever consumer instance is up next - a real
                       at-least-once duplicate-delivery scenario, not
                       simulated.
  crash_idempotent  - same crash mechanism, but checks a persisted
                       idempotency-key file before writing the side effect,
                       so the redelivery is detected and the business
                       effect is applied only once.
  ordered           - process with a per-message artificial delay (from
                       the 'delay_ms' field) and log completion order, for
                       the ordering experiment (R7-08).
"""
import json
import os
import time

import pika
import psycopg2

RABBIT_HOST = os.environ.get("RABBIT_HOST", "toxiproxy")
RABBIT_PORT = int(os.environ.get("RABBIT_PORT", "5672"))
RABBIT_USER = os.environ.get("RABBIT_USER", "guest")
RABBIT_PASS = os.environ.get("RABBIT_PASS", "guest")
CONSUMER_ID = os.environ.get("CONSUMER_ID", "consumer-1")

# R13-03 addition: "normal" processing now does one real DB write (through
# toxiproxy, same as R4) instead of just logging - this is what lets a real
# injected DB toxic slow down consumer throughput without touching AMQP.
DB_HOST = os.environ.get("DB_HOST", "toxiproxy")
DB_PORT = int(os.environ.get("DB_PORT", "5433"))
DB_NAME = os.environ.get("DB_NAME", "appdb")
DB_USER = os.environ.get("DB_USER", "appuser")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "apppass")


def db_write(order_id):
    conn = psycopg2.connect(host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
                             user=DB_USER, password=DB_PASSWORD, connect_timeout=10)
    cur = conn.cursor()
    cur.execute("CREATE TABLE IF NOT EXISTS processed_orders (id TEXT PRIMARY KEY, processed_at TIMESTAMPTZ DEFAULT now())")
    cur.execute("INSERT INTO processed_orders (id) VALUES (%s) ON CONFLICT DO NOTHING", (order_id,))
    conn.commit()
    conn.close()

SIDE_EFFECT_LOG = "/data/side_effects.log"
IDEMPOTENCY_STORE = "/data/processed_ids.log"
ORDER_LOG = "/data/order_completion.log"

RETRY_QUEUES = {
    1: ("orders-retry-1", 3000),
    2: ("orders-retry-2", 6000),
    3: ("orders-retry-3", 12000),
}


def log(msg):
    print(f"[{CONSUMER_ID}] {time.strftime('%H:%M:%S')} {msg}", flush=True)


def connect():
    creds = pika.PlainCredentials(RABBIT_USER, RABBIT_PASS)
    params = pika.ConnectionParameters(host=RABBIT_HOST, port=RABBIT_PORT, credentials=creds,
                                        heartbeat=5, blocked_connection_timeout=5)
    return pika.BlockingConnection(params)


def declare_topology(ch):
    ch.queue_declare(queue="orders", durable=True)
    ch.queue_declare(queue="orders-dlq", durable=True)
    for attempt, (qname, ttl) in RETRY_QUEUES.items():
        ch.queue_declare(queue=qname, durable=True, arguments={
            "x-message-ttl": ttl,
            "x-dead-letter-exchange": "",
            "x-dead-letter-routing-key": "orders",
        })


def already_processed(order_id):
    if not os.path.exists(IDEMPOTENCY_STORE):
        return False
    with open(IDEMPOTENCY_STORE) as f:
        return order_id in {line.strip() for line in f}


def mark_processed(order_id):
    with open(IDEMPOTENCY_STORE, "a") as f:
        f.write(order_id + "\n")


def append_side_effect(order_id, note):
    with open(SIDE_EFFECT_LOG, "a") as f:
        f.write(f"{time.time():.3f} {order_id} {note}\n")


def append_order_log(seq):
    with open(ORDER_LOG, "a") as f:
        f.write(f"{time.time():.3f} seq={seq} consumer={CONSUMER_ID}\n")


def on_message(ch, method, properties, body):
    msg = json.loads(body)
    order_id = msg.get("id", "unknown")
    mtype = msg.get("type", "normal")
    headers = properties.headers or {}
    attempt = headers.get("x-retry-attempt", 0)

    if mtype == "normal":
        t0 = time.time()
        db_write(order_id)
        elapsed = time.time() - t0
        log(f"NORMAL id={order_id} - processed, db_write={elapsed:.3f}s")
        append_side_effect(order_id, f"normal-processed db_write={elapsed:.3f}s")
        ch.basic_ack(method.delivery_tag)

    elif mtype == "poison":
        log(f"POISON id={order_id} attempt={attempt} - deliberately failing")
        next_attempt = attempt + 1
        if next_attempt > 3:
            log(f"POISON id={order_id} - exhausted 3 attempts, routing to orders-dlq")
            ch.basic_publish(exchange="", routing_key="orders-dlq", body=body,
                              properties=pika.BasicProperties(
                                  headers={"x-retry-attempt": next_attempt},
                                  delivery_mode=2))
        else:
            qname, ttl = RETRY_QUEUES[next_attempt]
            log(f"POISON id={order_id} - routing to {qname} (ttl={ttl}ms) for attempt {next_attempt}")
            ch.basic_publish(exchange="", routing_key=qname, body=body,
                              properties=pika.BasicProperties(
                                  headers={"x-retry-attempt": next_attempt},
                                  delivery_mode=2))
        ch.basic_ack(method.delivery_tag)

    elif mtype == "crash":
        log(f"CRASH id={order_id} - writing side effect then hard-exiting BEFORE ack")
        append_side_effect(order_id, "crash-no-idempotency")
        os._exit(1)

    elif mtype == "crash_idempotent":
        if already_processed(order_id):
            log(f"CRASH_IDEMPOTENT id={order_id} - already processed, SKIPPING duplicate side effect, acking")
            ch.basic_ack(method.delivery_tag)
            return
        log(f"CRASH_IDEMPOTENT id={order_id} - first time, writing side effect then hard-exiting BEFORE ack")
        mark_processed(order_id)
        append_side_effect(order_id, "crash-idempotent-first-time")
        os._exit(1)

    elif mtype == "ordered":
        delay_ms = msg.get("delay_ms", 0)
        seq = msg.get("seq")
        log(f"ORDERED id={order_id} seq={seq} - processing with {delay_ms}ms artificial delay")
        time.sleep(delay_ms / 1000.0)
        append_order_log(seq)
        ch.basic_ack(method.delivery_tag)

    else:
        log(f"UNKNOWN type={mtype} id={order_id} - acking without processing")
        ch.basic_ack(method.delivery_tag)


if __name__ == "__main__":
    os.makedirs("/data", exist_ok=True)
    log("starting, connecting to RabbitMQ...")
    conn = connect()
    channel = conn.channel()
    declare_topology(channel)
    channel.basic_qos(prefetch_count=1)
    channel.basic_consume(queue="orders", on_message_callback=on_message)
    log("ready, consuming from 'orders'")
    channel.start_consuming()
