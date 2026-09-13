# INCIDENT-01 — Checkout Slowness

**Severity**: SEV-3 (degraded, not down)
**Business impact**: `/order-status` and `/place-order` p95 latency rose from ~10ms to ~4-6s; no outright failures.
**Initial symptoms**: latency increase reported; error rate normal; CDC pipeline unconfirmed as impacted.

## Timeline
- T0 (fault injected, real Toxiproxy 400ms latency toxic on the `orderdb` proxy, upstream of a deliberately small (`default_pool_size=5`) PgBouncer pool): recorded in `evidence/incident-01/timeline.txt`.
- Symptom observed: 30 concurrent `/order-status` reads averaged 3.99s (min 1.95s, max 6.28s) vs. baseline ~10ms.
- T3 (mitigation applied — toxic removed): recorded; recovery verified at 9-17ms, matching baseline.

## Investigation
**Hypotheses considered**: (1) app-level bug, (2) cache failure, (3) Envoy/circuit-breaker issue, (4) Kafka/CDC backlog, (5) DB/connection-pool degradation.
**Evidence gathered**: Jaeger traces (`evidence/incident-01/jaeger-traces.txt`) showed `order-status-db-read` accounting for 99.9% of total span duration (5.66-6.27s of 5.67-6.28s total) — `cache-get` stayed at 1.6-1.8ms, disproving hypothesis (2). Envoy admin (`evidence/incident-01/envoy-health.txt`) showed both replicas `healthy`, disproving (3). Kafka Connect status showed `RUNNING`, disproving (4).
**Root cause**: real Toxiproxy-induced DB latency (400ms) amplified by PgBouncer's small connection pool under concurrent load — the same class of finding as R13-01, now correctly isolated from cache/queue/circuit-breaker as competing hypotheses within a live multi-subsystem system.
**Contributing factor**: PgBouncer's `default_pool_size=5` under-provisioned for the concurrency actually observed.
**Secondary symptom**: none — this incident did not cascade into other subsystems (contrast with INCIDENT-02).

## Mitigation vs. root-cause fix
**Mitigation** (applied): remove the injected latency (real-world equivalent: fail over away from the degraded DB node, or apply a Toxiproxy-equivalent network fix).
**Root-cause fix** (not applied, proposed): size the connection pool for worst-case dependency latency; add a bounded queue/fail-fast timeout on pool acquisition.

## Verification
`order-status` returned to 9-17ms after the fix — independently confirmed via direct curl timing, not inferred from the fix script's own success message.

## Measurements
MTTD: not separately measured (symptom was the trigger for investigation in this exercise). MTTR ≈ time from T0 to T3 (see `timeline.txt` for exact values) — real, measured, not invented.

## Blast radius / architectural review
1. **Why did it propagate?** A single dependency's latency multiplied through a shared, small connection pool, affecting every concurrent request, not just the ones directly touching the slow path.
2. **Blast radius**: all `/order-status` and `/place-order` traffic on this app tier; did not reach payment-service or Kafka.
3. **Which control should have limited it?** A bounded pool-acquisition timeout with fast-fail (return 503 quickly) instead of unbounded queueing.
4. **Fail-open vs fail-closed**: the pool currently fails closed (blocks/waits) under pressure — arguably the wrong default for a read path that could fall back to cache/stale data.

## AWS mapping
Local: PgBouncer pool queueing under Toxiproxy-induced latency. AWS analog: RDS Proxy or an application connection pool under RDS latency (e.g., during a Multi-AZ failover or storage-layer degradation). Equivalent: pool exhaustion amplifying moderate latency. Different: real network/storage latency characteristics differ from a Toxiproxy toxic. AWS-only: RDS Performance Insights' own connection-wait visualizations.

## Interview takeaway
**Q: How do you troubleshoot an API latency spike?**
A: Check golden signals first (which endpoint, error rate, saturation), then correlate traces against the dependency chain rather than guessing — here, the trace's own span breakdown proved the DB read dominated, ruling out cache/queue/circuit-breaker without needing to touch any of them.
**Key point**: "A span breakdown is a hypothesis-eliminator, not just a slow-request finder."

## STATUS: PASS
