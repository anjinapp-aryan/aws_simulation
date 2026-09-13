# R7 — Async Messaging Reliability (SQS/DLQ-equivalent)

Runnable lab: `labs/r7-messaging/`. Docs: `REUSE-AUDIT.md`, `ARCHITECTURE.md`, `R7-REPORT.md` (full results, real bugs found/fixed, PASS status).

```bash
cd labs/r7-messaging
./scripts/run.sh                          # start stack, create Toxiproxy proxy, start consumer
./scripts/status.sh
./scripts/produce.sh order-1 normal       # R7-01
./scripts/stop-consumer.sh                # R7-02
./scripts/start-consumer.sh
./scripts/poison-message.sh               # R7-03/04
./scripts/duplicate-delivery.sh with|without <id>   # R7-05
./scripts/network-failure.sh cut|latency|restore    # R7-06
./scripts/verify.sh
./scripts/cleanup.sh
```

Dashboards: RabbitMQ Management UI `:62672` (guest/guest), Grafana `:62300`, Prometheus `:62090`, Dozzle `:62888`.
