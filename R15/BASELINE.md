# R15 — Baseline

Captured before any fault injection (`evidence/baseline/baseline.txt`):
- Patroni: 3-node cluster, 1 Leader + 2 Replicas, `streaming`, 0 lag both Receive/Replay LSN.
- Both Debezium connectors (`order-outbox-connector`, `payment-outbox-connector`): `RUNNING`.
- Envoy: both `order-service-1`/`order-service-2` endpoints `healthy`.
- Full Saga verified end-to-end: `place-order` → `CREATED` → (real Kafka/Debezium relay, ~1.4-27s depending on consumer-group warmth, consistent with R11's own documented cold-start variance) → `CONFIRMED`.
- Cache-aside verified: first `/order-status` read `source: db`, second read `source: cache`.
- Real Jaeger traces present for `checkout`, `order-status`, `cache-get`, `order-status-db-read`.

This is the comparison point every incident's evidence is measured against.
