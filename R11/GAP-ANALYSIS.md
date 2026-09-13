# R11 Gap Analysis

## 1. R1-R10 coverage audit
Every layer covered so far operates on a **single** request/dependency at a time: one DB call (R4), one cache call (R6), one queue publish (R7), one traced request (R8), one circuit-protected call (R9), one orchestrated pod (R10). None of R1-R10 demonstrates **consistency across multiple services/data stores in one business operation** - the classic "update the order DB and publish an event, atomically" problem.

| Concept | Covered | Phase |
|---|---|---|
| Single DB write reliability | Yes | R4 |
| Single queue publish/consume reliability | Yes | R7 |
| Cross-service tracing of one request | Yes | R8 |
| Cross-service resilience (one call) | Yes | R9 |
| Orchestration of independently-running services | Yes | R10 |
| **Multi-step business transaction spanning DB + messaging, with partial-failure/compensation** | **No** | — |
| **Reliable event publication tied to a DB write (dual-write problem)** | **No** | — |
| Event streaming with partitions/consumer groups/replay | No (R7 used a queue, not a log) | — |

## 2. Remaining major gaps, ranked
1. **Distributed transactions / Saga pattern + Transactional Outbox (via real CDC)** - the single most common Staff/Architect distributed-systems interview question ("how do you keep a DB write and a message publish consistent without 2PC"), genuinely untouched, and naturally **composes** R4 (Postgres), R7 (messaging concepts), R9 (resilience), R10 (orchestration) into one new scenario rather than repeating any of them.
2. Event streaming (Kafka: partitions, consumer groups, replay, exactly-once) - real gap, but the outbox pattern's standard real-world implementation (Debezium + Kafka) naturally introduces Kafka anyway, folding this gap in rather than needing a separate phase.
3. Service mesh mTLS/zero-trust - R9 already used Envoy for circuit breaking; a security-focused mTLS follow-up is a good future candidate but a smaller delta right now.
4. Secrets management (Vault) - legitimate, independent future phase, doesn't depend on anything else.
5. Multi-region/DR/backup-restore - mostly NOT POSSIBLE LOCALLY, low hands-on ceiling, deprioritized (consistent with R10's autoscaling-gap reasoning).

## 3. Recommended R11 topic
**Distributed transactions: Transactional Outbox pattern with real Change-Data-Capture (Debezium), publishing to Kafka.** Demonstrates the "dual-write problem" (a service updating its DB and publishing an event are NOT atomic by default), the outbox-table solution, and a Saga-style multi-step flow with a deliberate partial failure and compensation, using real infrastructure throughout.

## 4. Why this wins
- Highest untouched Senior/Architect interview value in the entire remaining gap list.
- Composes 4 prior phases into a new scenario instead of repeating any of them.
- Strong real GitHub reuse: Debezium (real CDC, official Red Hat/Apache-2.0 project) and Kafka (official Apache project) are both mature, real infrastructure - not something to hand-roll.
- New, genuinely different failure modes: outbox-relay lag, duplicate event publication (Debezium is at-least-once, same lesson as R7 but at the CDC layer), a mid-Saga service failure requiring compensation - none of R1-R10 demonstrated compensating-transaction logic.

## 5. Why other candidates weren't selected
- Standalone Kafka/event-streaming: subsumed into R11 naturally via Debezium's standard pairing, avoiding a redundant phase.
- Service mesh mTLS: smaller delta over R9's existing Envoy work; queued as a good R12+ candidate.
- Secrets management: independent, doesn't address as large a gap; queued for later.
- Multi-region/DR: fidelity ceiling too low locally, per the same reasoning already applied in R10's gap analysis.
