# R11 Reuse Audit — Transactional Outbox / CDC / Saga

## Searches performed (real, GitHub Search API)
| Query | Result |
|---|---|
| `outbox pattern debezium docker compose demo` | 0 results |
| `saga pattern local simulation docker` | 0 results |

No integrated tool exists - consistent with every prior audit. Compose mature standalone projects.

## Candidate decision table

| Requirement | Project | License | Activity | UI | Decision | Reason |
|---|---|---|---|---|---|---|
| Change-Data-Capture (outbox relay) | `debezium/debezium` | Apache-2.0 (verified) | 13,108★, pushed 2026-09-11, very active | No dedicated UI (see below) | **REUSE** | Real, official, industry-standard CDC engine - reads the real Postgres WAL and publishes real change events; this IS the standard real-world outbox-pattern implementation, not something to hand-roll |
| Event log / streaming backbone | `apache/kafka` | Apache-2.0 (verified) | 33,709★, pushed 2026-09-12, very active | No bundled UI | **REUSE** | Official Apache project; Debezium's standard, first-class sink target - avoids inventing a CDC-to-broker bridge ourselves |
| Kafka visualization | `provectus/kafka-ui` | Apache-2.0 | pushed **2024-07-26** (~2 years stale) | Real topic/consumer-group UI | **REJECT (stale)** | Investigated further before rejecting outright - see below |
| Kafka visualization (active fork) | `kafbat/kafka-ui` | Apache-2.0 (verified) | 2,684★, pushed 2026-09-10, active | Real topic browser, consumer-group lag, message inspector | **REUSE** | Community-maintained continuation after the original went stale - same real capability, currently maintained |
| Debezium UI | `debezium/debezium-ui` | MIT | **archived** | Real connector management UI | **REJECT (archived)** | Explicitly archived by the Debezium project itself; connector setup will use Kafka Connect's REST API directly (a few `curl` calls, not a UI gap - the actual data visualization need is covered by kafbat/kafka-ui) |
| Transactional data store | `postgres` (already in stack) | PostgreSQL License | proven R4-R10 | pgweb available (R4) | **REUSE, carried forward unchanged** | The outbox table lives in the same real Postgres already used throughout this project |
| Fault injection | Toxiproxy | MIT | proven R4-R10 | — | **REUSE, carried forward unchanged** | Same real mechanism, new targets (Kafka broker port, Debezium's DB connection) |
| Saga orchestration logic | — | — | — | — | **BUILD (justified)** | Saga compensation logic is inherently business-specific state-machine code; no generic mature library fits our minimal-app pattern without pulling in a full framework (e.g., Java-only Eventuate/Axon) disproportionate to this lab's scope. Kept to the smallest possible explicit state machine. |

## Estimated custom code
~100-150 lines: two small services (Order service, Payment service) following the existing R4/R6/R7/R9 minimal-server pattern, each with a DB table + outbox table + a Saga step; a consumer that reads Kafka and drives the next Saga step or compensation. This is the largest single custom-code phase so far, but still thin application logic around real infrastructure (Postgres, Debezium, Kafka) - no custom CDC, no custom broker, no custom UI.

## Visualization strategy
`kafbat/kafka-ui` (real topic contents, consumer-group lag, partition state) is primary. Debezium connector/task status is real and queryable via Kafka Connect's own REST API (`GET /connectors/<name>/status`) - CLI evidence, documented as such rather than a missing visualization. Postgres outbox-table state via `pgweb` (reused from R4). Prometheus/Grafana reused if a meaningful metric exists (Kafka/Debezium JMX metrics), otherwise not forced.

## $0 proof
All components free/OSS: Debezium (Apache-2.0), Kafka (Apache-2.0, official Docker images), kafbat/kafka-ui (Apache-2.0), Postgres/Toxiproxy (already verified free). No AWS credential anywhere.

## What will NOT be built
No custom CDC engine, no custom message broker, no custom Kafka UI (kafbat reused), no generic Saga orchestration framework (kept to the minimum explicit state machine this lab needs), no Debezium UI (archived, rejected).
