# R13-01 — SPOILER — ROOT CAUSE (open only after investigating)

## What was injected
`inject.sh` added a real Toxiproxy `latency` toxic (400ms + 50ms jitter) on the `db` proxy (app → pgbouncer path), then fired 30 concurrent `/checkout` requests against a PgBouncer pool deliberately sized small (`default_pool_size = 5`, real PgBouncer config, same mechanism R4-03 already validated).

## Real observed evidence
- Baseline (pre-injection): `checkout` ~0.07s (`evidence/timeline.txt`).
- Under fault: 30 concurrent requests, **avg 4.00s, min 1.99s, max 6.04s** (`evidence/load-results.txt`) — a 30-85x multiplier over baseline, far larger than the 400ms nominal toxic.
- Real Jaeger traces (`evidence/jaeger-traces.json`): `checkout` span ≈5.8-6.0s, of which **`db-query` alone accounts for 5.8-5.97s** (99%+ of total). `cache-lookup` (~1-25ms) and `queue-publish` (~5-15ms) are unaffected — this rules out cache and queue as causes.

## Root cause
The 400ms toxic alone should only add 400ms per query. The observed 5.8s+ per request is **connection-pool queueing**, not raw query latency: with `default_pool_size=5` and pool_mode=transaction, each held connection (query time = ~50ms pg_sleep + 400ms toxic ≈ 450ms) can only serve 1 request at a time; with 30 concurrent requests and 5 slots, later requests queue behind ~5-6 sequential 450ms turns before their own transaction even starts — this compounds because PgBouncer's own client wait time is invisible as a separate trace span, it's absorbed into the single `db-query` span (a real, honest limitation of span-level attribution when pooling happens below the instrumented layer — matches a genuine production blind spot).

This is exactly the pattern the architecture predicted: DB latency itself (400ms) is a modest contributor; the dominant effect is **downstream connection-pool exhaustion amplifying a moderate latency injection into a severe one**.

## Immediate mitigation
`fix.sh` removes the latency toxic. Confirmed recovery: checkout requests return to sub-100ms after the toxic is removed.

## Permanent fix / prevention
- Size the connection pool for worst-case dependency latency, not just steady-state throughput (`default_pool_size` should account for `max_expected_latency * expected_concurrency`).
- Add a pool-saturation alert (PgBouncer's own `SHOW POOLS` `cl_waiting` count) as a leading indicator, independent of end-to-end latency, so the pool-vs-query distinction doesn't require a full trace-level investigation next time.
- Consider a bounded queue / fail-fast timeout on pool acquisition rather than unbounded queueing, so a DB slowdown degrades gracefully (fast 503s) instead of silently multiplying latency for every caller.

## AWS mapping
RDS connection latency (e.g., from a failover, or Multi-AZ replica lag) combined with an application-tier connection pool (RDS Proxy, PgBouncer sidecar, or a JDBC pool) sized for steady-state, not degraded-state — a very common real-world RDS incident shape.
