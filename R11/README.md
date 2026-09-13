# R11 — Transactional Outbox / CDC / Saga

Runnable lab: `labs/r11-outbox-saga/`. Docs: `GAP-ANALYSIS.md`, `REUSE-AUDIT.md`, `ARCHITECTURE.md`, `R11-REPORT.md` (full results, real bugs found/fixed, PASS status).

```bash
cd labs/r11-outbox-saga
./scripts/run.sh                              # start stack, register real Debezium connectors
./scripts/status.sh
./scripts/place-order.sh order-1 0            # R11-01 (0=succeed, 1=fail_payment)
./scripts/break-kafka.sh cut|latency|restore  # R11-02/03
./scripts/connector-control.sh pause|resume   # R11-06
./scripts/consumer-control.sh stop|start      # R11-08
./scripts/duplicate-event.sh                  # R11-05
./scripts/verify.sh order-1
./scripts/cleanup.sh
```

Dashboards: Kafka UI `:55080`, pgweb (order-db) `:55081`, pgweb (payment-db) `:55082`, Debezium Connect REST `:55083/connectors`.
