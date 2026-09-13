# R11 — Proposed Architecture (pending approval, nothing built yet)

## Scenario
An order-placement Saga spanning two independently-owned services and databases - the canonical distributed-transaction teaching scenario.

## Diagram
```
Client
  |
  v
Order Service (ADAPTED - R4/R6/R7/R9 minimal-server pattern)
  |
  +-- writes Order row + Outbox row, ONE local Postgres transaction (real atomicity)
  |
  v
Postgres (order-db)  <-- REUSED unchanged, R4 config
  |
  v
Debezium (NEW, real CDC) -- reads real WAL, captures the outbox table
  |
  v
Kafka (NEW, real event log) -- topic: order-events
  |
  v
Payment Service (ADAPTED - same minimal pattern)
  |
  +-- consumes OrderCreated, attempts payment, writes Payment row + Outbox row
  |     (own local transaction, own DB: payment-db, REUSED Postgres config)
  |
  v
Debezium -> Kafka -- topic: payment-events
  |
  v
Order Service consumes PaymentCompleted -> confirms order
              OR consumes PaymentFailed -> runs COMPENSATION (cancels order)

Fault injection: Toxiproxy (REUSED, R4-R10 pattern) on DB and Kafka connections
Visualization: kafbat/kafka-ui (NEW, real topic/consumer-group/message browser)
               pgweb (REUSED, R4) on both databases
               Kafka Connect REST API (real, for Debezium connector status)
```

## Component classification
| Component | Status |
|---|---|
| Debezium (Kafka Connect + Debezium Postgres connector) | **NEW** |
| Kafka (official Apache image) | **NEW** |
| kafbat/kafka-ui | **NEW** |
| Order Service, Payment Service | **ADAPTED** - existing minimal-server pattern + outbox table + Saga step logic (~100-150 lines total, the largest custom-code allocation so far, justified in `R11/REUSE-AUDIT.md`) |
| Postgres (x2 logical DBs), PgBouncer, Toxiproxy, pgweb | **REUSED unchanged**, R4 config |

## Data/request flow
Client -> Order Service -> (local Postgres transaction: Order + Outbox row) -> Debezium (WAL capture) -> Kafka -> Payment Service -> (local Postgres transaction: Payment + Outbox row) -> Debezium -> Kafka -> Order Service (confirm or compensate).

## Failure injection points
Toxiproxy on the Order-DB and Payment-DB connections (reused mechanism), Toxiproxy on Debezium's Kafka connection, Kafka Connect REST API to pause/resume the Debezium connector task (real connector lifecycle control), a deliberate `FAIL_PAYMENT=true` flag on the Payment Service to force the compensation path.

## Visualization points
`kafka-ui` (real topic contents, consumer-group lag, partition assignment), `pgweb` (real outbox/order/payment table state on both DBs), Kafka Connect REST API (`GET /connectors/.../status`, real connector/task health).

## Experiments (9)

Mapped against the user's proposed 10-item list: R11-01/02/03/06/07/09 map directly; the proposed "connector pause+recovery" and "consumer stopped+backlog+recovery" are kept as two **distinct** experiments below (R11-06 = CDC-layer backlog via Kafka Connect, R11-08 = consumer-layer backlog via a stopped Payment Service) since they exercise genuinely different failure points, not the same mechanism twice; "end-to-end visualization" is folded in as R11-09, a guided walkthrough rather than a new mechanism to break.

| ID | Purpose | What we break | Visualization | AWS mapping | Fidelity |
|---|---|---|---|---|---|
| R11-01 | Happy-path Saga | — | kafka-ui shows real events flow through both topics; pgweb shows Order status progressing Created->Paid->Confirmed | DynamoDB Streams/RDS + EventBridge outbox pattern | REAL |
| R11-02 | Prove the dual-write problem is solved | Cut Kafka connectivity via Toxiproxy right after the DB commit | pgweb shows the outbox row durably committed despite Kafka being down; kafka-ui shows it appear the instant connectivity restores - no event lost | The exact problem RDS+EventBridge/DynamoDB Streams outbox patterns solve | REAL |
| R11-03 | Debezium relay lag (measured) | Toxiproxy latency on Debezium's DB connection | Compare Postgres commit timestamp vs. kafka-ui's message timestamp - real measured lag, not assumed | CDC replication lag, a real operational metric in production outbox systems | REAL |
| R11-04 | Compensating transaction (Saga failure path) | `FAIL_PAYMENT=true` | pgweb shows Order transition to Cancelled after a real PaymentFailed event round-trip | The core Saga pattern - what EventBridge/Step Functions Saga orchestration solves at the AWS control-plane level | REAL mechanism, BEHAVIOR-EQUIVALENT to a managed Saga orchestrator |
| R11-05 | Duplicate event / consumer idempotency | Reset a Kafka consumer group offset to force reprocessing | Logs show the event redelivered; pgweb shows no duplicate Payment row, reusing the idempotency-key pattern proven in R7 | At-least-once delivery is Kafka's real, standard guarantee - same as SQS/Kinesis | REAL |
| R11-06 | Debezium connector failure/recovery | Pause the connector via Kafka Connect REST API while new outbox rows accumulate | kafka-ui shows zero new messages during the pause, then a real backlog drain the moment it's resumed | CDC pipeline outage and recovery - a real operational scenario for any Debezium-based system, including on AWS DMS/MSK Connect | REAL |
| R11-07 | Consumer group scaling / rebalance | Scale Payment Service replicas | kafka-ui's consumer-group view shows real partition reassignment across instances | Kinesis/MSK consumer scaling and shard/partition assignment | REAL |
| R11-08 | Consumer-layer failure + Kafka-native backlog + recovery (distinct from R11-06's CDC-layer pause) | Stop the Payment Service consumer entirely while Order events keep publishing | kafka-ui's consumer-group lag metric climbs in real time (messages already IN Kafka, unlike R11-06 where they never left Postgres); restarting the consumer shows real lag drain | Kafka/MSK consumer-group lag is a first-class real operational metric distinct from a CDC pipeline outage | REAL |
| R11-09 | End-to-end visualization walkthrough (capstone, not a new failure mechanism) | — | Guided pass through kafka-ui + pgweb together, tracing one order's full real lifecycle (DB row -> outbox row -> CDC capture -> Kafka message -> consumer -> Saga state -> confirm/compensate) in one sitting | Reinforces the whole pipeline as a single mental model before the report | REAL |

## REAL vs BEHAVIOR-EQUIVALENT vs NOT POSSIBLE LOCALLY
- **REAL**: Debezium's actual WAL-based CDC, real Kafka topics/partitions/consumer groups, real Postgres transactional atomicity, real at-least-once delivery and duplicate handling.
- **BEHAVIOR-EQUIVALENT**: this outbox+CDC+Kafka pipeline standing in for AWS's DynamoDB Streams/RDS+EventBridge outbox patterns, or MSK Connect running Debezium (a real, common AWS deployment pattern - not a stretch); the Saga compensation logic standing in for what Step Functions/EventBridge orchestration would coordinate at a managed level.
- **NOT POSSIBLE LOCALLY**: AWS DMS/MSK Connect's own managed connector infrastructure, EventBridge's managed event bus and cross-account routing, Step Functions' managed Saga/state-machine execution history and console.

## Per-component AWS mapping (Rule 13)
| Local component | AWS equivalent | REAL | BEHAVIOR-EQUIVALENT | NOT POSSIBLE LOCALLY |
|---|---|---|---|---|
| Kafka | Amazon MSK | Real topics/partitions/consumer-groups/offsets | MSK's managed broker lifecycle | MSK's own control plane, IAM auth, multi-AZ broker placement |
| Postgres | Amazon RDS/Aurora PostgreSQL | Real WAL, real transactional atomicity | RDS-managed instance | RDS Multi-AZ failover, automated backups, IAM DB auth |
| Debezium (Kafka Connect) | AWS DMS (CDC mode) / MSK Connect running Debezium | Real WAL-based CDC | Debezium-on-MSK-Connect is a real, common AWS pattern - not a stretch | DMS's own managed replication instance and console |
| kafbat/kafka-ui | No single first-party AWS equivalent (CloudWatch + MSK console cover parts) | Real topic/consumer-group browsing | — | CloudWatch's own MSK metrics/alarms integration |
| Saga compensation logic (our code) | Step Functions / EventBridge-orchestrated Saga | Real state transitions, real compensating writes | Standing in for what a managed orchestrator would coordinate | Step Functions' managed execution history, retry policies, and console |

## $0 proof strategy
Debezium, Kafka, kafbat/kafka-ui all free/self-hosted Apache-2.0. Postgres/Toxiproxy/pgweb already verified free in R4-R10. No AWS credential anywhere.

## Cleanup strategy
`docker compose down -v` + verify via `docker ps -a`/`docker network ls`/`docker volume ls` grep-empty, same convention as R4-R9.

---

## R11 ARCHITECTURE READY FOR APPROVAL

Waiting for **"R11 ARCHITECTURE APPROVED"** before writing any docker-compose.yml, scripts, or application code.
