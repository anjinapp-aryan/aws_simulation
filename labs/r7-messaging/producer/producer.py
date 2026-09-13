#!/usr/bin/env python3
"""R7 producer - thin adapter around pika. Publishes one message to the
real 'orders' queue and exits. No custom broker/queue logic - just a
publish call, run as a one-off container by scripts/produce.sh.
"""
import json
import os
import sys
import time

import pika

RABBIT_HOST = os.environ.get("RABBIT_HOST", "toxiproxy")
RABBIT_PORT = int(os.environ.get("RABBIT_PORT", "5672"))
RABBIT_USER = os.environ.get("RABBIT_USER", "guest")
RABBIT_PASS = os.environ.get("RABBIT_PASS", "guest")


def main():
    order_id = sys.argv[1] if len(sys.argv) > 1 else f"order-{int(time.time()*1000)}"
    mtype = sys.argv[2] if len(sys.argv) > 2 else "normal"
    seq = sys.argv[3] if len(sys.argv) > 3 else None
    delay_ms = sys.argv[4] if len(sys.argv) > 4 else "0"

    body = {"id": order_id, "type": mtype}
    if seq is not None:
        body["seq"] = int(seq)
    if mtype == "ordered":
        body["delay_ms"] = int(delay_ms)

    creds = pika.PlainCredentials(RABBIT_USER, RABBIT_PASS)
    params = pika.ConnectionParameters(host=RABBIT_HOST, port=RABBIT_PORT, credentials=creds)
    conn = pika.BlockingConnection(params)
    ch = conn.channel()
    ch.queue_declare(queue="orders", durable=True)
    ch.basic_publish(exchange="", routing_key="orders", body=json.dumps(body),
                      properties=pika.BasicProperties(delivery_mode=2))
    print(f"published id={order_id} type={mtype} seq={seq}")
    conn.close()


if __name__ == "__main__":
    main()
