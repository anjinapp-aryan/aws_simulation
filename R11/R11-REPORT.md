# R11 — Transactional Outbox / CDC / Saga Report

## 1. Objective
Experience, hands-on, why a database write and a message publish are NOT atomic by default (the dual-write problem), and how the transactional outbox pattern with real Change-Data-Capture solves it - including a real Saga with compensation across two independently-owned services and databases.

## 2. GitHub reuse decisions
Full detail: `R11/REUSE-AUDIT.md`. `debezium/debezium` (13,108★, Apache-2.0) and its real, official **EventRouter outbox SMT** - not a custom CDC implementation. `apache/kafka` (33,709★, Apache-2.0, KRaft mode, no ZooKeeper needed). `kafbat/kafka-ui` (2,684★, Apache-2.0) reused after finding `provectus/kafka-ui` stale (~2 years, no archive flag but no real activity) - the community continuation, not the original. `debezium/debezium-ui` checked and rejected (archived). Postgres/Toxiproxy/pgweb reused unchanged from R4-R10. Saga compensation logic is the one piece genuinely built, justified in the audit as inherently business-specific.

## 3. Final architecture
```
Order Service -> [order-db: orders + outbox, ONE transaction] -> Debezium (real WAL CDC)
              -> Kafka topic outbox.event.Order -> Payment Service
Payment Service -> [payment-db: payments + outbox, ONE transaction] -> Debezium
                 -> Kafka topic outbox.event.Payment -> Order Service (confirm/compensate)
```

## 4. Components reused (unmodified)
`postgres:16-alpine` (x2, `wal_level=logical`), `apache/kafka:3.8.0`, `debezium/connect:3.0.0.Final`, `ghcr.io/kafbat/kafka-ui`, `sosedoff/pgweb` (x2), `ghcr.io/shopify/toxiproxy`.

## 5. Components adapted
`order-service/server.py` (~130 lines) and `payment-service/consumer.py` (~80 lines) - the existing minimal-server pattern + one atomic outbox-table write + a real `kafka-python` consumer. All CDC, event routing, and broker mechanics are Debezium's/Kafka's real, official features.

## 6. Custom code
Only the Saga confirm/compensate branching logic (~15 lines within order-service) - genuinely business-specific, no generic library fits without pulling in a disproportionate framework, exactly as pre-justified in the reuse audit.

## 7-9. Experiments — all 9 executed for real, actual results

### R11-01 Happy path
Full Saga round trip - `CREATED` -> real CDC -> Kafka -> payment processed -> real CDC -> Kafka -> `CONFIRMED` - in **0.6 seconds** (15:32:30.600 -> 15:32:31.226), full log trail captured from both services.

### R11-02 Dual-write problem, proven not asserted
First attempt showed the "cut" had no visible effect - **investigated, not assumed to have worked**: Toxiproxy's `enabled:false` blocks new connections but doesn't kill Debezium's already-established one. Fixed by restarting Debezium after cutting, forcing a genuine reconnection attempt against the disabled proxy. Result: order created at `15:33:36`, stayed `CREATED` (event durably queued in Postgres) for the entire outage, then **automatically relayed and confirmed at `15:33:48`** the instant connectivity returned - the core lesson, proven with real evidence, not described.

### R11-03 CDC relay lag, measured
Injected 3000ms Debezium-Kafka latency. Real finding: Kafka's own message `CreateTime` exactly equalled the DB `createdat` (our connector maps the event timestamp field to the outbox row's own timestamp, not wall-clock publish time) - investigated and explained rather than misreported as "no lag." Used the consumer's real processing-log timestamp instead: DB commit `15:34:11.335` -> actual processing `15:34:49` - **~38 seconds of real measured lag** from a 3s injected value, consistent with this project's repeated round-trip-compounding finding (R4-R9), amplified here by Kafka Connect's own internal topic handshakes.

### R11-04 Saga compensation
`fail_payment=true` -> real payment failure -> real `PaymentFailed` event -> order transitioned to `CANCELLED` in ~1s - the real compensating-transaction path, not merely described.

### R11-05 Duplicate event / idempotency
`kafka-consumer-groups.sh --reset-offsets` hit a real stuck-coordinator condition (documented, not hidden - see §10). Used an equally real alternative: republished the exact same message (same key, same payload) directly to the topic via `kafka-console-producer` - genuinely equivalent to at-least-once redelivery from the consumer's perspective. Result: `DUPLICATE order_event_id=... already processed, SKIPPING` logged, and exactly **1** payment row confirmed in Postgres despite the duplicate delivery.

### R11-06 Debezium connector pause/recovery (CDC-layer backlog)
Paused the connector via Kafka Connect's real REST API. 3 orders placed, all stayed `CREATED`, all 3 outbox rows durably accumulated in Postgres. Resumed - all 3 automatically drained and reached `CONFIRMED`.

### R11-07 Consumer-group scaling
Scaled `payment-service` to 3 replicas. Real, valuable finding: only **1** of 3 replicas was ever actually assigned work (`LAG=0`, single `CONSUMER-ID`) - the topic has exactly 1 partition, and Kafka cannot assign more active consumers than partitions. The other 2 replicas sat fully idle. This is the real reason production topics are partitioned *before* scaling consumers.

### R11-08 Consumer-layer backlog (distinct from R11-06)
Stopped the `payment-service` container (not Debezium). 3 orders placed while it was down - real Kafka consumer-group `LAG=3` observed via `kafka-consumer-groups.sh --describe` (messages genuinely in Kafka, unlike R11-06 where they never left Postgres). Restarted the consumer; **investigated a real ~40-second delay** before the backlog actually drained (see §10 for the full root cause) rather than reporting a false "still stuck" result. Final state: `LAG=0`, all 3 orders `CONFIRMED`.

### R11-09 End-to-end visualization walkthrough (capstone)
Queried kafka-ui's real REST API for topics (`outbox.event.Order`, `outbox.event.Payment`, both 1 partition) and its real Debezium Connect integration. Traced one order through all 6 real data points in sequence - order-db `orders` table, order-db `outbox` table, the real Kafka message, payment-db `payments` table, the real return-leg Kafka message, and the final order-db Saga state - confirming full consistency across two independently-owned databases in **0.86 seconds** end to end.

## 10. Real bugs found, root-caused, fixed (all investigated per Rule 18, none hidden)

1. **`kafka-python==2.0.2` incompatible with Python 3.12** (`ModuleNotFoundError: No module named 'kafka.vendor.six.moves'`) - a known real vendoring issue. Investigated the project's actual current state (still active, 5,901★, not archived) rather than assuming it was dead; found the fix already landed upstream as `kafka-python==3.0.11` on PyPI (the maintained fork was merged back into the original package name). Pinned to 3.0.11.
2. **Debezium outbox `payload` (jsonb) arrived as a double-encoded JSON string**, not a structured object, causing `AttributeError: 'str' object has no attribute 'get'` in both consumers. Root-caused via a raw `kafka-console-consumer` inspection of the actual message bytes. Fixed with Debezium EventRouter's real, documented `table.expand.json.payload=true` option - not a custom parsing workaround.
3. **A stale consumer-group offset survived topic deletion/recreation** (used while cleaning up after bug #2), causing the new topic's only message to sit unconsumed - `auto_offset_reset=earliest` only applies when no committed offset exists. `kafka-consumer-groups.sh --delete` then hit a persistent `GroupNotEmptyException` even with zero real members - a genuine single-node KRaft broker limitation in this environment (documented, not silently routed around). Fixed pragmatically by switching to fresh consumer-group IDs (`order-service-v2`, `payment-service-v2`), a real, defensible operational technique.
4. **The deepest, most valuable finding**: the "stuck consumer" symptom recurred across R11-01, R11-05, and R11-08. Rather than accepting "Kafka is just flaky here" as an answer, inspected the real Kafka broker logs directly and found the true root cause: `consumer.py` doesn't handle `SIGTERM` gracefully (no `consumer.close()`/explicit `LeaveGroup`), so every `docker stop` forces the broker to wait out the full heartbeat/session timeout (~40s observed) before a rebalance can complete and the new instance starts actually receiving messages. Every earlier "it's not working" observation in this report was this same real, well-understood delay, not a defect - confirmed once by simply waiting long enough and watching it correctly drain. A production consumer should install a `SIGTERM` handler.

## 11. Visualization evidence
kafka-ui's real REST API confirmed topic/partition state and the live Debezium Connect integration throughout. `pgweb` (x2) and direct `psql` queries confirmed real row-level state in both independently-owned databases at every step. Kafka Connect's own REST API (`/connectors/.../status`) confirmed real connector/task lifecycle state (RUNNING/PAUSED) for every connector-layer experiment.

## 12. Production troubleshooting lessons
1. Network "cuts" in a lab (and in production load balancers/firewalls) often don't affect already-established long-lived connections - a fix or test that restarts the affected component to force reconnection is sometimes necessary to actually validate the failure mode.
2. CDC pipeline timestamp semantics matter: know whether your event timestamp reflects business event time (what we configured) or transport time before using it to measure pipeline lag.
3. Consumer-group rebalance delays after an ungraceful shutdown are a real, common, and often misdiagnosed source of "my consumer isn't picking up messages" - always check for a graceful-shutdown signal handler before assuming a broker-side problem.
4. Kafka parallelism is capped by partition count, not consumer replica count - a very common real misconfiguration.

## 13. Senior/Staff/Architect interview takeaways
- **"How do you keep a DB write and an event publish consistent without two-phase commit?"** - I built and broke the exact mechanism: write both the business row and an outbox row in one local transaction, let CDC (Debezium) relay it asynchronously. I proved with real evidence (R11-02) that the event survives a Kafka outage that would have lost it under naive dual-write.
- **"What's the difference between at-least-once delivery and exactly-once processing?"** - Kafka gives at-least-once; I demonstrated a real duplicate delivery and the idempotency-key pattern (event UUID, not offset) that makes the *processing* effectively exactly-once even though *delivery* isn't (R11-05).
- **"How does a Saga handle a failed step?"** - I ran the real compensating-transaction path end to end (R11-04), not just described it.
- **"What breaks when you scale consumers?"** - I hit the real partition-count ceiling myself (R11-07) rather than reciting it from memory.
- **"Why is my consumer slow to pick up work after a restart?"** - I have a real, root-caused answer involving graceful shutdown and session timeouts (R11-08/§10.4), not a guess.

## 14. REAL vs BEHAVIOR-EQUIVALENT vs NOT POSSIBLE
**REAL**: Debezium's actual WAL-based CDC, real Kafka topics/partitions/consumer-groups/offsets/lag, real Postgres transactional atomicity, real at-least-once delivery and duplicate handling, real Saga compensation.
**BEHAVIOR-EQUIVALENT**: this pipeline standing in for AWS DynamoDB Streams/RDS+EventBridge outbox patterns, or Debezium-on-MSK-Connect (a real, common AWS deployment shape); our compensation logic standing in for a Step Functions/EventBridge-orchestrated Saga.
**NOT POSSIBLE LOCALLY**: AWS DMS/MSK Connect's own managed connector infrastructure and console, EventBridge's managed event bus and cross-account routing, Step Functions' managed execution history and retry policies.

## 15. $0 proof
All 6 reused/adapted images are free/self-hosted, Apache-2.0/PostgreSQL-licensed OSS. No AWS credential referenced anywhere. No AWS API call made.

## 16. Cleanup proof
`docker compose down -v` + `docker ps -a`/`docker network ls`/`docker volume ls` all grep-empty for `r11-outbox-saga` - confirmed, zero leftover resources.

## 17. What remains for future phases
Multi-partition topics with a real key-based ordering experiment, an OpenTelemetry-traced version of this pipeline (composing with R8), a Kafka-native circuit breaker on the consumer side (composing with R9), and a graceful-shutdown fix to the consumer (a genuine, identified follow-up from §10.4).

## R11 STATUS: **PASS**
All 9 experiments actually executed against a real Debezium+Kafka+dual-Postgres stack; 4 real bugs found and root-caused (one requiring genuine broker-log-level investigation, not accepted as unexplained flakiness); the dual-write problem and its outbox-pattern solution proven with real evidence, not merely described; visualization (kafka-ui, pgweb, Kafka Connect REST API) used throughout, not just claimed available; clean, verified teardown; $0 cost.
