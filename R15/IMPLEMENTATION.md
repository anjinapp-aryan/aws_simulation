# R15 — Implementation (Step 1 & 2)

## Step 1 — Reuse inventory
| Component | Source | REUSED / ADAPTED |
|---|---|---|
| Patroni + etcd + HAProxy (3-node HA Postgres) | R14 (`labs/r14-ha-dr/patroni-src`, official `patroni/patroni` repo) | REUSED, unmodified compose; rebuilt image (removed after R14 cleanup) |
| Kafka + Debezium + Kafka UI | R11/R13 | REUSED, unmodified |
| payment-service + payment-db | R11 | REUSED, unmodified (copied verbatim) |
| order-service | R11 (Saga/outbox) + R8 (OTel) + R6/R13 (cache-aside) | ADAPTED — merged the three proven patterns into one app, pointed at Patroni's HAProxy instead of a single Postgres instance; added a bounded (configurable) retry loop for R15-05, the only genuinely new logic |
| Valkey | R6/R13 | REUSED, unmodified |
| Toxiproxy | R4/R6/R7/R8/R9/R11/R13/R14 | REUSED, unmodified — two proxies (`orderdb`, `cache`) |
| Envoy (2 app replicas, outlier detection) | R9/R13 | REUSED config pattern, endpoints repointed at `order-service-1/2` |
| Prometheus/Grafana/Jaeger/Dozzle/pgweb | R4-R9/R11/R13 | REUSED, unmodified |
| pgBackRest | R14 | To be installed on the Patroni leader for Incident 6, exact R14 setup |

## Real bugs found and fixed while building the standing system
1. **Debezium `createdat` type mismatch** — the outbox table used `TIMESTAMPTZ`; Debezium's EventRouter SMT requires the source column to map to Kafka Connect's `int64` (epoch-millis) logical type, which only `TIMESTAMP` (no timezone) gets via Debezium's default column mapping. `TIMESTAMPTZ` maps to a `ZonedTimestamp` (string) type, causing `DataException: Field 'createdat' is not of type INT64` and putting the connector's task into `FAILED` state (while the connector itself stayed `RUNNING`, a real, easy-to-miss distinction). Root-caused via the real Debezium/Kafka Connect stack trace; fixed by matching R11's own proven `TIMESTAMP` column type.
2. **Patroni's demo cluster defaults to `wal_level=replica`**, not `logical` — Debezium's `order-outbox-connector` needs logical replication on the order-side DB. Fixed via Patroni's own REST API (`PATCH /config`), same technique as R14 Experiment 5's `archive_mode` fix, followed by a rolling `patronictl restart` of all three members.
3. **First-order-relay latency variance** (not a bug — an observation worth recording): the first order after a cold Kafka-consumer-group start took ~27s to reach CONFIRMED (matches R11's own documented consumer-group rebalance finding); a subsequent order confirmed in ~1.4s once the consumer group had stabilized. This variance is itself real evidence relevant to MTTD/MTTR baselining for the incidents below — a "just wait and check again" reflex could look like a false recovery if checked too early.

## Baseline (Step 3) — captured, all healthy
`R15/evidence/baseline/baseline.txt`: Patroni 3-node cluster (1 Leader, 2 Replicas, 0 lag), both Debezium connectors `RUNNING`, both Envoy-fronted app replicas `healthy`, real Jaeger traces showing `cache-get`/`order-status-db-read` span breakdown, full Saga verified end-to-end (`CREATED` → `CONFIRMED`), cache-aside verified (`source: db` → `source: cache` on second read).

Standing system confirmed healthy. Proceeding to Incident 1.
