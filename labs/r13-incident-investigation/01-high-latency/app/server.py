#!/usr/bin/env python3
"""R8 app - extends the R4/R6/R7 minimal-server pattern with real
OpenTelemetry instrumentation (official SDK, not a custom tracer).
One endpoint, /checkout, with real spans around a real Valkey cache
lookup, a real Postgres query, and a real RabbitMQ publish that injects
W3C trace context into the message headers (real propagation, not
assumed to work).
"""
import json
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pika
import psycopg2
import redis
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.propagate import inject
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.trace.sampling import ParentBased, TraceIdRatioBased
from opentelemetry.trace import Status, StatusCode

DB_HOST = os.environ.get("DB_HOST", "pgbouncer")
DB_PORT = int(os.environ.get("DB_PORT", "6432"))
DB_NAME = os.environ.get("DB_NAME", "appdb")
DB_USER = os.environ.get("DB_USER", "appuser")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "apppass")

CACHE_HOST = os.environ.get("CACHE_HOST", "toxiproxy-cache")
CACHE_PORT = int(os.environ.get("CACHE_PORT", "6379"))

RABBIT_HOST = os.environ.get("RABBIT_HOST", "rabbitmq")
RABBIT_PORT = int(os.environ.get("RABBIT_PORT", "5672"))

OTLP_ENDPOINT = os.environ.get("OTLP_ENDPOINT", "http://jaeger:4318/v1/traces")
SAMPLE_RATIO = float(os.environ.get("SAMPLE_RATIO", "1.0"))

resource = Resource.create({"service.name": "r8-app"})
provider = TracerProvider(resource=resource, sampler=ParentBased(TraceIdRatioBased(SAMPLE_RATIO)))
provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=OTLP_ENDPOINT)))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer("r8-app")


def cache_lookup(order_id):
    with tracer.start_as_current_span("cache-lookup") as span:
        span.set_attribute("cache.key", f"order:{order_id}")
        r = redis.Redis(host=CACHE_HOST, port=CACHE_PORT, socket_timeout=1, socket_connect_timeout=1)
        val = r.get(f"order:{order_id}")
        span.set_attribute("cache.hit", val is not None)
        return val


def db_query(order_id):
    with tracer.start_as_current_span("db-query") as span:
        span.set_attribute("db.system", "postgresql")
        span.set_attribute("db.statement", "SELECT pg_sleep(0.05), now()")
        conn = psycopg2.connect(host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
                                 user=DB_USER, password=DB_PASSWORD, connect_timeout=3)
        cur = conn.cursor()
        cur.execute("SELECT pg_sleep(0.05), now();")
        row = cur.fetchone()
        conn.close()
        return f"order-{order_id} computed_at={row[1]}"


def queue_publish(order_id):
    with tracer.start_as_current_span("queue-publish") as span:
        span.set_attribute("messaging.system", "rabbitmq")
        span.set_attribute("messaging.destination", "orders")
        headers = {}
        inject(headers)  # real W3C trace-context injection into message headers
        creds = pika.PlainCredentials("guest", "guest")
        conn = pika.BlockingConnection(pika.ConnectionParameters(host=RABBIT_HOST, port=RABBIT_PORT, credentials=creds))
        ch = conn.channel()
        ch.queue_declare(queue="orders", durable=True)
        body = json.dumps({"order_id": order_id})
        ch.basic_publish(exchange="", routing_key="orders", body=body,
                          properties=pika.BasicProperties(delivery_mode=2, headers=headers))
        conn.close()
        span.set_attribute("traceparent", headers.get("traceparent", ""))


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

        if not self.path.startswith("/checkout"):
            self._write(200, {"message": "GET /checkout?id=1 to trigger a traced request"})
            return

        order_id = "1"
        fail = "fail=1" in self.path
        if "id=" in self.path:
            order_id = self.path.split("id=", 1)[1].split("&", 1)[0]

        with tracer.start_as_current_span("checkout") as span:
            span.set_attribute("order.id", order_id)
            trace_id = format(span.get_span_context().trace_id, "032x")
            start = time.time()
            try:
                if fail:
                    raise RuntimeError("simulated business logic failure")

                try:
                    cached = cache_lookup(order_id)
                except Exception as e:
                    span.record_exception(e)
                    span.add_event("cache_failed_open_to_db")
                    cached = None

                value = db_query(order_id)
                queue_publish(order_id)

                elapsed = time.time() - start
                self._write(200, {"order_id": order_id, "value": value, "trace_id": trace_id,
                                   "elapsed": round(elapsed, 3)})
            except Exception as e:
                span.record_exception(e)
                span.set_status(Status(StatusCode.ERROR, str(e)))
                elapsed = time.time() - start
                self._write(500, {"error": str(e), "trace_id": trace_id, "elapsed": round(elapsed, 3)})

    def log_message(self, fmt, *args):
        print(f"[app] {self.address_string()} - {fmt % args}", flush=True)


if __name__ == "__main__":
    print(f"[app] starting, sampling ratio={SAMPLE_RATIO}, otlp={OTLP_ENDPOINT}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
