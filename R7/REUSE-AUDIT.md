# R7 Reuse Audit — Async Messaging Reliability (SQS/DLQ-equivalent)

## Phase A — Gap matrix (R1-R6 coverage)

| Capability | Simulated? | Phase | Hands-on? | Visualization? | Remaining gap |
|---|---|---|---|---|---|
| IAM/task credentials | Yes | R1 | Yes | CLI/logs | — |
| Load balancing / health checks | Yes | R2/R3 | Yes | Traefik dashboard | — |
| Container lifecycle (OOM/crash/restart) | Yes | R3/R5 | Yes | Dozzle/cAdvisor/docker stats | — |
| DB connectivity/pooling/latency | Yes | R4 | Yes | Grafana/pgweb | — |
| CPU/memory pressure + cascading failure | Yes | R5 | Yes | Grafana/Traefik | — |
| Caching, cache-aside, stampede, failover | Yes | R6 | Yes | redis-commander/Grafana | — |
| **Async messaging (SQS/SNS-equivalent)** | **No** | — | — | — | **Full gap** |
| **DLQ / poison message handling** | **No** | — | — | — | **Full gap** |
| **Retry/backoff semantics** | **No** | — | — | — | **Full gap** |
| **At-least-once delivery / duplicate handling / idempotency** | **No** | — | — | — | **Full gap** |
| **Message ordering** | **No** | — | — | — | **Full gap** |
| **Consumer failure / redelivery / lag** | **No** | — | — | — | **Full gap** |
| Circuit breakers | No | — | — | — | Partial gap (deferred, see below) |
| Distributed tracing | No | — | — | — | Deferred since R5 (Jaeger), still open |
| API Gateway / rate limiting | No | — | — | — | Open gap |

**R7 relevance**: Async messaging reliability is the single largest, highest-interview-value, completely untouched gap after R1-R6, and is a near-daily topic in Senior/Lead/Architect AWS interviews (SQS visibility timeout, DLQ redrive, exactly-once vs at-least-once, ordering with FIFO queues, consumer scaling). Selected as R7's topic.

## Phase B — GitHub reuse audit (refreshed, not blindly trusted from the first pass)

Re-ran the search with different phrasing before implementing, specifically looking for a better/newer candidate:
| Query | Result |
|---|---|
| `sqs compatible local broker docker` | 0 results |
| `aws sqs simulator open source` | 0 results |

No superior candidate found. One note worth recording: this repo's Track 1 (`connectivity-test`/`serverless-api`/`event-pipeline`) already uses **Ministack** for real SQS-API-shaped behavior (see root `CLAUDE.md`) — but per that same file, "these two tracks are unrelated in content; don't try to unify them," and Track 2's whole methodology (chaos injection, visualization-first, `labs/rX-*` pattern) is what R7 needs, not API-shape fidelity. RabbitMQ remains the right choice: real broker semantics (ack/nack/DLQ/redelivery) plus a real bundled Management UI, which Ministack's SQS mock does not provide. Decision unchanged.



Real searches run (GitHub Search API):
| Query | Result |
|---|---|
| `sqs local simulation dlq docker` | 0 results |
| `message queue chaos docker retry backoff` | 0 results |
| `kafka chaos docker consumer lag simulation` | 0 results |

Consistent with every prior audit: no integrated tool exists, compose mature components.

| Repo | Stars | License | Last push | Capability | Decision |
|---|---|---|---|---|---|
| `rabbitmq/rabbitmq-server` | 13,849 | **MPL 2.0** (verified via actual LICENSE file — GitHub badge wrongly showed NOASSERTION) | 2026-09-11, active | Real mature message broker, real queues, real DLQ (dead-letter-exchange), real consumer ack/nack/requeue semantics, closest open-source analog to SQS's queue+redrive model | **REUSE** — official Docker image ships a built-in **Management UI** (real, mature, no custom dashboard needed) |
| RabbitMQ built-in `rabbitmq_prometheus` plugin | — | same as above | — | Official, ships with RabbitMQ itself, exposes real queue-depth/consumer/ack-rate metrics | **REUSE** — preferred over any third-party exporter |
| `kbudde/rabbitmq_exporter` | 721 | MIT | **archived 2026-07**, no longer maintained | Third-party Prometheus exporter | **REJECT** — archived, and RabbitMQ's own built-in plugin (above) makes it unnecessary anyway |
| `apache/kafka` | 33,708 | Apache-2.0 | active | Real distributed log, closer analog to Kinesis (ordered partitions, consumer groups, replay) than to SQS | **REFERENCE** — right tool for a future "event streaming/Kinesis" phase, not for SQS/DLQ-style queue semantics, which is R7's actual target |
| `redpanda-data/redpanda` | 12,534 | **BSL (source-available, not fully open)**, verified via actual license docs | active | Kafka-API-compatible, single-binary, lighter than Kafka | **REJECT for this phase** — license caution (same category as Redis in R6) and not the right semantic fit (queue vs log) regardless |
| `obsidiandynamics/kafdrop` | 6,156 | Apache-2.0 | active | Kafka UI | **REJECT** — not needed, RabbitMQ's own Management UI covers R7 |
| Toxiproxy (Shopify) | — | MIT | — | Real TCP fault injection | **REUSE, carried forward unchanged from R4/R5/R6** — new target: RabbitMQ's AMQP port |
| Prometheus/Grafana/Dozzle | — | — | — | Metrics/logs, proven | **REUSE, carried forward unchanged** |

## Visualization decision
RabbitMQ's own **Management UI** (official, bundled, real-time queue depth/consumer/message-rate dashboard) is the primary visualization — this alone satisfies "a GitHub project's dashboard must be preferred over building our own." Grafana (fed by RabbitMQ's built-in Prometheus plugin) is added only for consistency with the existing R4-R6 stack and to correlate messaging metrics alongside container/DB metrics already there. No custom UI.

## Estimated custom code
One producer endpoint + one consumer process added to the existing minimal app pattern (~50-70 lines total, using `pika`, the mature official-recommended Python AMQP client) — implementing: publish, consume-with-manual-ack, deliberate nack-to-DLQ on a "poison" message, and a retry-with-backoff consumer variant. Sized consistently with every prior phase's single-purpose additions.

## $0 proof
RabbitMQ (MPL 2.0), its built-in Prometheus plugin, Toxiproxy/Grafana/Prometheus/Dozzle (all previously verified free) — no AWS credential, no paid service, no AWS API call.

## What will NOT be built
No Kafka/Redpanda deployment (reference-only, deferred to a future streaming-focused phase), no custom message-queue UI (RabbitMQ Management UI covers it), no circuit-breaker library integration (deferred — would need real instrumentation, out of R7's scope), no distributed tracing (still deferred from R5, not resolved here either).
