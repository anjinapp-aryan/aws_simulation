# R13 — Architecture: Production Troubleshooting / Incident Investigation

## 1. Design principle

Every experiment is presented to the investigator by **symptom only**. The hidden fault (below, spoiler-labeled) is injected by a script the investigator does not read first. Root cause must be found via the same evidence a real on-call engineer would use: Grafana, Jaeger, RabbitMQ UI, Kafka UI, Dozzle, `kubectl`, Hubble — never by reading the injection script. Each experiment reuses, unmodified, mechanisms already proven real in R4/R6/R7/R8/R9/R10/R11/R12; **zero new infrastructure mechanisms are built**.

## 2. Composed architecture

```
labs/r13-incident-investigation/
  scenarios/<name>/inject.sh      <- hidden fault injection (investigator doesn't read this first)
  scenarios/<name>/investigate.md <- blank runbook the investigator fills in live
  scenarios/<name>/reveal.md      <- root cause + fix, opened only AFTER investigation
  docker-compose.yml (or kind manifests, per scenario) <- reuses R4/R6/R7/R8/R9/R11 compose
  shared: Grafana+Prometheus (R4/R5/R6/R9), Jaeger (R8), RabbitMQ UI (R7), Kafka UI (R11), Dozzle
```

Each scenario is its own minimal compose stack (or reuses R10/R12's `kind` cluster for the two K8s-native scenarios), composed from **existing** R-lab service definitions — copied/wired, not rewritten.

## 3. Experiments (8, one per category the user listed)

Format per the required interview structure: symptom → first check → metrics → logs → traces → dependency → hypotheses → elimination → root cause → immediate mitigation → permanent fix → prevention.

### R13-01 — High latency (reuses R4 DB+Toxiproxy, R8 Jaeger, Grafana)
**Symptom (shown to investigator):** p99 API latency alarm fires in Grafana; users report slow checkout.
**Hidden fault (spoiler):** Toxiproxy injects +400ms latency on the Postgres connection. This is small enough that a naive glance at DB query time looks "fine," but the app's connection pool (fixed size) saturates under the added per-query hold time, so most of the *observed* latency is actually **queueing for a pool connection**, not the query itself — the investigator must find this distinction via Jaeger span breakdown (`pool_wait` span vs `db_query` span), not assume "DB is slow."
**Investigation path:** Grafana p99 panel → Jaeger trace waterfall (pool-wait span dominates) → correlate to DB latency panel (mildly elevated, not proportional) → hypothesis: pool exhaustion, not raw DB slowness → confirm via pool-in-use metric.
**Fix:** remove Toxiproxy latency toxic (mitigation); permanent fix discussion: pool sizing / timeout tuning / connection multiplexing (PgBouncer, already in R4).
**AWS mapping:** RDS latency → app-tier connection-pool exhaustion, a real, common AWS incident shape.
**Fidelity: REAL** (Toxiproxy applies real TCP-level latency; pool exhaustion is real application behavior, not simulated).

### R13-02 — HTTP 5xx spike (reuses R9 Envoy/PyBreaker)
**Symptom:** error-rate panel spikes; some requests succeed, some 502.
**Hidden fault (spoiler):** Toxiproxy injects intermittent timeouts on one backend replica only. Because R9 already documented that a single-replica cluster hits Envoy's `panic threshold` (outlier ejection has no effect with <2 healthy hosts), the 5xx spike here is deliberately run against a **2-replica** backend so ejection actually shifts traffic — investigator must notice the 5xx rate drops to near-zero once ejection engages, then find the still-unhealthy replica.
**Investigation path:** Grafana error-rate panel → Envoy admin `/clusters` outlier stats → Jaeger shows failing spans concentrated on one span's `peer.address` → Dozzle logs on that one container show timeouts.
**Fix:** restart/replace the bad replica (mitigation); permanent: fix whatever caused that replica's dependency timeout, add better health checks.
**AWS mapping:** ALB target-group health check ejecting one unhealthy EC2/ECS target — the mechanism R9 already validated behavior-equivalent to.
**Fidelity: REAL** (Envoy outlier ejection is genuine, not scripted).

### R13-03 — Queue backlog (reuses R7 RabbitMQ)
**Symptom:** RabbitMQ UI shows `orders` queue depth climbing, consumers appear "connected."
**Hidden fault (spoiler):** the consumer is alive but each message now takes far longer to process because its downstream DB call is throttled via Toxiproxy — consumer throughput drops below publish rate, so the queue *looks* stalled but is actually **rate-mismatched**, not dead.
**Investigation path:** RabbitMQ UI (consumer count normal, ack rate low, not zero) → Dozzle consumer logs (still processing, just slow) → Jaeger span on consumer's DB call shows elevated latency → correlate timing to when backlog started growing.
**Fix:** relieve DB latency (mitigation); permanent: add consumer autoscaling or a slow-consumer alarm on ack-rate-vs-publish-rate divergence, not just "consumer connected" health checks.
**AWS mapping:** SQS backlog from a Lambda/consumer whose downstream (RDS) is degraded — the classic "consumer looks healthy but isn't keeping up" SQS incident.
**Fidelity: REAL.**

### R13-04 — Resource pressure (reuses R10 `kind` OOMKill/HPA)
**Symptom:** pod restarts visible in `kubectl get pods` (`RESTARTS` climbing); intermittent request failures during restarts.
**Hidden fault (spoiler):** memory `limit` set intentionally tight and load generator ramps request size (larger payloads) over time — first restarts look random, but memory usage climbs monotonically per-pod until `OOMKilled`, and it recurs on every replacement pod because the limit, not a code bug, is the constraint.
**Investigation path:** `kubectl get pods` (`OOMKilled`/Exit 137) → `kubectl describe pod` (real event) → Grafana/metrics-server memory panel shows monotonic climb, not a spike → correlate to load generator's payload-size log.
**Fix:** raise the memory limit or fix payload size (mitigation); permanent: right-size limits from real profiling, add a memory-growth alert before OOMKill.
**AWS mapping:** EKS pod OOMKill from undersized limits — directly reuses R10's already-proven real `Exit Code: 137` finding.
**Fidelity: REAL** (same real OOMKilled mechanism R10 already validated).

### R13-05 — Cascading failure (reuses R9 breaker + R11 Saga, multi-hop)
**Symptom:** order-service latency climbs, then payment-service starts logging compensation events for orders that should have succeeded.
**Hidden fault (spoiler):** Toxiproxy DB latency on order-service's DB → order-service's Saga step times out waiting for its own DB write confirmation → it fires a compensating "cancel" event even though the original write would have eventually succeeded → payment-service correctly (per its own logic) compensates a payment for an order that wasn't actually broken. This is a genuine **timeout-vs-eventual-consistency** cascading failure, not a crash.
**Investigation path:** Grafana order-service latency → Jaeger trace shows DB span exceeding the Saga step's timeout → Kafka UI shows a `cancel` outbox event immediately following a slow `create` event for the same order ID → correlate timestamps to prove the DB was merely slow, not failed.
**Fix:** raise the Saga step timeout or fix DB latency (mitigation); permanent: don't compensate on timeout alone without confirming the original operation actually failed (idempotent confirm-before-compensate pattern).
**AWS mapping:** Step Functions/Saga timeout misfiring a compensating transaction under transient RDS latency — a real, subtle distributed-transaction design flaw.
**Fidelity: REAL** (reuses R11's actually-working Debezium/Kafka Saga end to end).

### R13-06 — Network/security failure (reuses R12 Cilium/Hubble)
**Symptom:** backend intermittently can't reach database; some requests succeed, some time out, no code/config was "obviously" changed.
**Hidden fault (spoiler):** a new pod replica gets deployed with a label typo (`tier: backend-v2` instead of `tier: backend`) — the existing `CiliumNetworkPolicy` selector only matches `tier: backend`, so the new replica silently has **no** allow rule and is denied, while the old, correctly-labeled replicas keep working — a real, common "policy didn't get updated for the new rollout" incident, intermittent because only some replicas are affected.
**Investigation path:** Grafana/app error rate shows partial (not total) failure → `kubectl get pods --show-labels` reveals the label mismatch → Hubble flow data on the mislabeled pod shows `EGRESS DENIED` while sibling pods show `FORWARDED` → root cause confirmed by comparing labels across pods, not by re-reading the policy alone.
**Fix:** relabel the pod (mitigation); permanent: CI check that new Deployment label sets match existing NetworkPolicy selectors before rollout.
**AWS mapping:** Security Group not attached to a new ASG launch template / ENI — the same "rollout forgot to carry over network config" incident shape, real via R12's already-proven enforcement.
**Fidelity: REAL** (genuine Cilium enforcement + genuine label mismatch, not scripted denial).

### R13-07 — Cache failure (reuses R6 Valkey)
**Symptom:** DB load (query rate, CPU) spikes even though request volume is flat; app latency creeps up.
**Hidden fault (spoiler):** Valkey's `maxmemory-policy` combined with a tightened `maxmemory` limit causes aggressive eviction of hot keys under normal traffic — cache hit ratio silently collapses (not a crash, not a connection failure) so every request falls through to the DB, which is the real R6 cache-aside pattern's genuine behavior under memory pressure, not a fault injected into the app.
**Investigation path:** Grafana DB query-rate panel spikes with flat request volume → Grafana cache hit-ratio panel (if present) or Valkey `INFO stats` (`keyspace_hits`/`keyspace_misses`) shows the ratio collapse → correlate timing to a `maxmemory` config change event.
**Fix:** raise `maxmemory` / fix eviction policy (mitigation); permanent: alert on cache hit-ratio drop as a leading indicator before DB load becomes the visible symptom.
**AWS mapping:** ElastiCache eviction under undersized node class — a real, common ElastiCache sizing incident.
**Fidelity: REAL** (genuine Valkey eviction behavior under real memory pressure).

### R13-08 — Distributed transaction failure (reuses R11 Debezium/Kafka Saga)
**Symptom:** customers report orders stuck "processing" indefinitely; no errors in order-service's own logs.
**Hidden fault (spoiler):** the Debezium connector process is paused (not crashed — a real `PAUSED` state via the Kafka Connect REST API) so outbox rows are written correctly (order-service's own transaction succeeds, no error) but never relayed to Kafka — a genuinely silent failure exactly matching R11's own documented "dual-write problem" proof, now hidden rather than demonstrated.
**Investigation path:** app/order-service logs show nothing wrong (this is the trap — first-check-metrics/logs looks clean) → Kafka UI shows the `outbox` topic has stopped receiving new messages despite the outbox table (checked via `psql`/pgweb) growing → Kafka Connect REST API (`GET /connectors/order-connector/status`) reveals `state: PAUSED` → root cause confirmed.
**Fix:** resume the connector (mitigation); permanent: alert on connector state != RUNNING, and/or alert on outbox-table unprocessed-row age exceeding a threshold as a backstop independent of connector health.
**AWS mapping:** DMS/CDC task stopped silently while the source DB keeps accepting writes — a real, easy-to-miss AWS incident category.
**Fidelity: REAL** (reuses R11's real Debezium connector and its real REST-managed lifecycle state).

## 4. What's explicitly NOT built

No new app code beyond what R1-R12 already have. No new dashboards. No new fault-injection mechanism — every "hidden fault" above is one of: Toxiproxy toxic, K8s resource limit, pod label edit, Valkey config change, or a real Kafka Connect REST pause call. The only new code is the thin `inject.sh` harness per scenario (a few lines each, calling already-proven APIs) and blank `investigate.md`/`reveal.md` runbook templates.

## 5. REAL / BEHAVIOR-EQUIVALENT / NOT POSSIBLE LOCALLY

All 8 experiments are **REAL** — every fault is a genuine infrastructure-level condition (real Toxiproxy toxic, real OOMKill, real Cilium policy denial, real Valkey eviction, real paused Kafka Connect task), and every diagnostic signal is real tool output (real Grafana/Jaeger/RabbitMQ UI/Kafka UI/Hubble data), not scripted/asserted. **NOT POSSIBLE LOCALLY**: correlating against a real on-call paging system (PagerDuty/Opsgenee) and real multi-week historical baselines for anomaly detection — noted as out of scope, not attempted.

## 6. $0 and cleanup

All components are exactly the free, already-proven-$0 images from R4/R6/R7/R8/R9/R10/R11/R12. Each scenario gets its own `docker compose down -v` (or `kind delete cluster` for the two K8s scenarios) + explicit zero-leftover verification, per standing rule.

## 7. Next step

Awaiting **"R13 ARCHITECTURE APPROVED"** before any implementation (no code, compose files, or manifests have been written yet — this document and the two audits above are the complete Phase A deliverable).
