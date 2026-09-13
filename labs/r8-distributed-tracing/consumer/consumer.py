#!/usr/bin/env python3
"""R8 consumer - extends R7's consumer pattern with real OpenTelemetry
trace-context extraction from message headers, so the consumer's span
becomes a real child of the producer's original trace (or, if extraction
fails, a fresh disconnected trace - determined experimentally, not
assumed, per R8-05).
"""
import json
import os
import time

import pika
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.propagate import extract
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

RABBIT_HOST = os.environ.get("RABBIT_HOST", "rabbitmq")
RABBIT_PORT = int(os.environ.get("RABBIT_PORT", "5672"))
OTLP_ENDPOINT = os.environ.get("OTLP_ENDPOINT", "http://jaeger:4318/v1/traces")

resource = Resource.create({"service.name": "r8-consumer"})
provider = TracerProvider(resource=resource)
provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=OTLP_ENDPOINT)))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer("r8-consumer")


def log(msg):
    print(f"[consumer] {time.strftime('%H:%M:%S')} {msg}", flush=True)


def on_message(ch, method, properties, body):
    headers = properties.headers or {}
    ctx = extract(headers)  # real W3C trace-context extraction
    with tracer.start_as_current_span("consume-order", context=ctx) as span:
        msg = json.loads(body)
        order_id = msg.get("order_id")
        trace_id = format(span.get_span_context().trace_id, "032x")
        span.set_attribute("order.id", order_id)
        span.set_attribute("messaging.system", "rabbitmq")
        log(f"processing order_id={order_id} trace_id={trace_id} propagated_headers={bool(headers)}")
        time.sleep(0.05)
        ch.basic_ack(method.delivery_tag)


def connect():
    creds = pika.PlainCredentials("guest", "guest")
    params = pika.ConnectionParameters(host=RABBIT_HOST, port=RABBIT_PORT, credentials=creds,
                                        heartbeat=5, blocked_connection_timeout=5)
    return pika.BlockingConnection(params)


if __name__ == "__main__":
    log("starting, connecting to RabbitMQ...")
    conn = connect()
    channel = conn.channel()
    channel.queue_declare(queue="orders", durable=True)
    channel.basic_qos(prefetch_count=1)
    channel.basic_consume(queue="orders", on_message_callback=on_message)
    log("ready, consuming from 'orders'")
    channel.start_consuming()
