# R13-07 — SPOILER — ROOT CAUSE

## What was injected
`inject.sh` set real Valkey config: `CONFIG SET maxmemory 1mb` + `CONFIG SET maxmemory-policy allkeys-lru`, then issued 600 real `/cached-item` requests (200 distinct keys x 3 rounds).

## Real observed evidence
- `evidence/hit-miss.txt`: **600 MISS, 0 HIT** out of 600 requests.
- `evidence/valkey-info-stats.txt`: `keyspace_hits:1` (from the pre-fault baseline check), `keyspace_misses:601`, `evicted_keys:0`.
- `DBSIZE` immediately after the run: **0** — no keys survived in the cache at all.
- `used_memory:1565464` (~1.5MB) vs. configured `maxmemory:1048576` (1MB) — Valkey's own baseline process overhead alone already exceeds the configured limit.

## Root cause
`maxmemory` was set below Valkey's own baseline memory footprint, so every `SETEX` the app issues after a DB read fails to actually persist a usable cache entry (the app's own `except Exception: pass` around `r.setex` — a deliberate fail-open design already documented in R6 — silently swallows this). The result: **every single request is a cache miss**, indistinguishable at the HTTP layer from normal operation (still `200 MISS ... elapsed=0.1xxs`, never an error) because the app is working exactly as designed — degrading gracefully to the DB rather than failing. The only visible symptom is Postgres taking 100% of the read load instead of the small fraction it should, and Grafana/Postgres metrics would show query-rate/CPU rising with flat request volume — exactly the incident as originally reported, now explained.

This differs from a "crash" or "connection refused" cache failure (already covered structurally by R6's own failover experiments) — here the cache is fully up and reachable, just **functionally useless** due to a sizing misconfiguration, which is a materially harder failure mode to notice because nothing looks "down."

## Immediate mitigation
Restore a sane `maxmemory` (`fix.sh`) — cache writes start succeeding again immediately.

## Permanent fix / prevention
- Alert on cache hit ratio (`keyspace_hits / (keyspace_hits + keyspace_misses)`) directly, not just on cache reachability — reachability checks would have shown this cache as perfectly healthy throughout the incident.
- Alert on `used_memory` approaching `maxmemory` as a leading indicator before hit ratio collapses to near-zero.
- Don't silently swallow cache-write failures in application code without at least incrementing a metric/counter — the current fail-open design (intentionally correct for availability) hides this class of incident from the app's own logs entirely.

## AWS mapping
ElastiCache node undersized for its working set (or a `maxmemory`-equivalent misconfiguration during a resize) causing silent eviction/write-failure while the node itself reports healthy — a real, easy-to-miss ElastiCache capacity-planning incident.
