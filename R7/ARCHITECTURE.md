# R7 — Proposed Architecture (pending approval, nothing built yet)

## Topology
```
Client
  |
  v
Traefik (reused, R2/R3/R5/R6 pattern)
  |
  v
app (extends R6's app: + /publish endpoint, + a separate consumer process)
  |
  v
Toxiproxy (reused - new proxy: rabbitmq-proxy -> rabbitmq:5672)
  |
  v
RabbitMQ (real broker: main queue + DLQ via dead-letter-exchange)
  |
  v
consumer (separate small process: manual ack/nack, retry-with-backoff,
          poison-message -> DLQ after N attempts)

Observability (all reused):
  RabbitMQ Management UI (built-in, real-time queue depth/consumers/rates)
  RabbitMQ's own rabbitmq_prometheus plugin -> Prometheus -> Grafana
  Dozzle (consumer/producer logs)
```

## Why this shape (smallest useful)
- RabbitMQ's Management UI is the primary "SEE the system" mechanism — real, bundled, no custom dashboard.
- Toxiproxy sits in front of RabbitMQ's AMQP port exactly like it already sits in front of Postgres (R4) and Valkey (R6) — same mechanism, new target, zero new fault-injection code.
- Producer is one new endpoint on the existing app; consumer is one small standalone script (same minimal-server discipline as every prior phase) — not a new framework.
- DLQ is configured via RabbitMQ's native dead-letter-exchange feature (real broker capability, not simulated).

## Experiments (7)

| ID | Objective | Real mechanism | Fidelity |
|---|---|---|---|
| R7-01 Normal flow | Publish -> consume -> ack | Real AMQP publish/consume, real queue depth drop in Management UI | REAL |
| R7-02 Consumer down | Stop the consumer process, publish more messages | Real queue depth growth (visible live in Management UI), no consumer to drain it | REAL |
| R7-03 Poison message / DLQ | Publish a message the consumer deliberately nacks N times | Real dead-letter-exchange routes it to the real DLQ after max retries | REAL |
| R7-04 Retry with backoff | Consumer nacks with increasing delay (RabbitMQ delayed-requeue or per-attempt sleep) | Real redelivery count increments, real backoff timing measured | REAL |
| R7-05 Broker latency/unavailability | Toxiproxy injects AMQP latency, then cuts connectivity | Real publish/consume failures and reconnection behavior | REAL |
| R7-06 Duplicate delivery / idempotency | Force a redelivery (ack lost/consumer crash mid-processing) and show the consumer's idempotency key check | Real at-least-once semantics, real duplicate detection logic | REAL / BEHAVIOR-EQUIVALENT (idempotency key mechanism is our design choice, same one used in real SQS consumers) |
| R7-07 Recovery + queue drain | Restart consumer, restore broker | Real queue depth returns to 0, DLQ inspected via Management UI | REAL |

## REAL vs BEHAVIOR-EQUIVALENT vs NOT POSSIBLE (architecture-level)
- **REAL**: RabbitMQ broker, AMQP protocol, queue depth, DLQ routing, consumer ack/nack, Toxiproxy-injected network faults, actual redelivery counts.
- **BEHAVIOR-EQUIVALENT**: RabbitMQ's queue+DLQ model standing in for SQS+DLQ (different protocol/API, same semantic pattern); our idempotency-key consumer logic standing in for a production dedup strategy.
- **NOT POSSIBLE LOCALLY**: SQS's actual API/visibility-timeout mechanics, AWS's own DLQ redrive tooling, CloudWatch SQS metrics, SNS fan-out to real AWS subscribers.

## $0 proof (architecture-level)
RabbitMQ MPL 2.0, all other components already verified free in R2-R6. No AWS credential/API anywhere in the proposed compose file or scripts.

## What will NOT be built
No Kafka/Redpanda, no custom queue-browser UI, no circuit-breaker library, no distributed tracing.

---

Waiting for **"R7 ARCHITECTURE APPROVED"** before writing any docker-compose.yml, scripts, or app code.
