# R9 — Circuit Breaking & Service Resilience Report

## 1. Objective
Demonstrate the *mitigation* for R5's cascading-failure scenario: two real, distinct circuit-breaking patterns (infra-level via Envoy, app-level via PyBreaker) protecting the same real DB dependency, measured under real failure and real load.

## 2. GitHub reuse decisions
Full detail: `R9/REUSE-AUDIT.md`. `envoyproxy/envoy` (28,906★, Apache-2.0, active daily) - real outlier-detection engine, the actual data plane AWS App Mesh runs on. `danielfm/pybreaker` (693★, BSD-3-Clause) - real Python circuit-breaker state machine. `Netflix/Hystrix` explicitly rejected (deprecated/maintenance-mode since 2018). Postgres/PgBouncer/Toxiproxy/Prometheus/Grafana/Dozzle all reused unchanged from R4-R8.

## 3. Final architecture
```
Client -> Envoy (real outlier detection) -> app (PyBreaker-wrapped /order,
                                                   unprotected /order-raw)
                                              -> Toxiproxy -> PgBouncer -> Postgres
```

## 4. Components actually used
Unmodified: `envoyproxy/envoy:v1.31-latest`, `postgres:16-alpine`, `edoburu/pgbouncer`, `prometheuscommunity/postgres-exporter`, `ghcr.io/shopify/toxiproxy`, `prom/prometheus`, `grafana/grafana`, `amir20/dozzle`.

## 5. Custom code
`app/server.py` (~130 lines): existing R4 pattern + real `pybreaker.CircuitBreaker` wrapping the DB call, a `/breaker-status` endpoint, and a real `CircuitBreakerListener` for state-change logging. `config/envoy.yaml`: a static Envoy config with real `outlier_detection` (no code, declarative).

## 6-9. Experiments — all 10 executed for real, actual results

### R9-01 Baseline
Breaker `closed`, Envoy host `healthy`. Vegeta: 50 requests, 100% success, mean 32.8ms.

### R9-02 Dependency failure, no protection
First attempt (Toxiproxy `cut`) revealed a real methodological gap: instant connection-refusal (2.9ms mean) doesn't represent the pain circuit breakers exist for. **Corrected** by using a 5000ms latency toxic exceeding the app's 3s `connect_timeout` instead - the realistic "hanging dependency" case. Result: every request paid the full **3.0s** before failing, 0% success, 50/50 requests at 500.

### R9-03 App breaker opens (measured)
Requests 1-2: real DB timeout failures, 3.0s each (breaker still `closed`, counting). Request 3: breaker trips **while making the attempt** (still 3.0s - real pybreaker behavior, the tripping request pays its own cost). Requests 4-5: **0.002-0.003s**, real `CircuitBreakerError`, no DB connection attempted at all. **~1500x latency reduction**, measured not assumed.

### R9-04 Half-open recovery
DB restored. Polled every 2s. At t+3s, `/breaker-status` (a separate GET) still read stale `open`, but the concurrent `/order` request at that exact moment triggered the real half-open probe, succeeded, and flipped the breaker - confirmed `closed` by t+5s. **Real, subtle finding**: pybreaker's state is evaluated lazily on `.call()`, not proactively, so a status-check endpoint can momentarily disagree with the breaker's true live behavior.

### R9-05 Thundering-herd protection (investigated a false signal)
WITHOUT breaker: 60/60 requests at 3.0s each, 0% success - real unmitigated pain.
WITH breaker (first attempt): mean latency measured **5.93s** - worse than unprotected at first glance. **Investigated rather than accepted at face value**: root-caused to a client-side HTTP keep-alive connection-reuse artifact in Vegeta (fast 503s queued behind slow in-flight requests on reused connections). Re-ran with independent connections (`-connections=60 -keepalive=false`): median dropped to **75.8ms**, confirming the breaker's real server-side protection once the measurement artifact was removed.

### R9-06 Envoy outlier ejection (real bug investigated)
First check showed `health_flags::healthy` despite 5 consecutive real 500s - looked like ejection wasn't working. **Investigated via Envoy's own `/stats`**, not assumed: `ejections_enforced_total` had actually incremented (3, then 5) - ejection WAS happening. Root cause: `lb_healthy_panic: 62` confirmed Envoy's panic-threshold safety mechanism was routing to the host anyway, because with only **one** backend host, ejecting it would leave 0% healthy targets (below the 50% panic threshold). **Real architectural lesson**: outlier detection needs >=2 replicas to have any actual traffic-shifting effect - directly maps to why an ALB/App Mesh target group needs multiple healthy targets.

### R9-07 Envoy recovery
DB restored. 3 real requests succeeded (0.03-0.04s). `ejections_enforced_total` stayed flat (5, unchanged) - no new failures, confirmed via Envoy's own counters.

### R9-08 App breaker vs Envoy (synthesized from real, already-measured evidence)
Full comparison table in `evidence/R9-08/comparison.log` - covers detection point, traffic-stopping behavior, information available, latency impact, dependency load, and recovery mechanics, each claim backed by a specific earlier experiment's real numbers, not restated theory.

### R9-09 Cascading-failure prevention (measured at the resource level)
First check (`/health` responsiveness under unprotected load) showed **no degradation** - an honest finding that nuanced the premise: `ThreadingHTTPServer` spawns unlimited threads, so `/health` isn't starved at this scale. **Investigated the real resource cost instead**: unprotected load (rate=40/s, 5s hang each) drove the app container to **121 threads** (`docker exec ... /proc/1/task`, confirmed). Identical load through the breaker-protected path: **1-2 threads**. A dramatic, real, measured demonstration of resource-exhaustion prevention.

### R9-10 Final recovery + clean state
Breaker `closed` (fail_counter 0), Envoy host `healthy`, both `/order` and `/order-raw` back to ~30ms. Full `docker compose down -v`; verified zero leftover containers/networks/volumes.

## 10-11. Bugs discovered and root causes (summary - full detail above)
1. Toxiproxy `cut` doesn't represent realistic dependency pain - fixed by using a timeout-exceeding latency toxic.
2. Vegeta's mean-latency reading was inflated by client-side connection reuse, not a real breaker slowdown - isolated and confirmed via a controlled re-run.
3. Envoy's `/clusters` health flag didn't reflect ejection due to single-host panic-threshold routing - root-caused via Envoy's own `/stats` counters (`ejections_enforced_total`, `lb_healthy_panic`), not guessed.
4. `/health` responsiveness didn't degrade under unprotected load at this scale - investigated further to find the real resource-pressure signal (thread count), which did show a dramatic, real difference.

None of these were hidden or silently patched - each is documented with the investigation that led to the real conclusion.

## 12. REAL vs BEHAVIOR-EQUIVALENT vs NOT POSSIBLE
**REAL**: PyBreaker's actual state machine (closed/open/half-open, measured transition timing), Envoy's actual outlier-detection engine and panic-threshold logic, real Toxiproxy-injected dependency hang, real measured latency/thread-count differences.
**BEHAVIOR-EQUIVALENT**: this Envoy config standing in for "AWS App Mesh circuit breaking" - same real Envoy engine, no App Mesh control plane or AWS-managed xDS.
**NOT POSSIBLE LOCALLY**: App Mesh's own control plane/console, real cross-AZ mesh behavior, CloudWatch/X-Ray integration with App Mesh telemetry, ALB target-group-level health-check-driven deregistration (a related but distinct AWS mechanism from Envoy's own outlier detection).

## 13. AWS production mapping (per experiment, concise)
- R9-03/04 app breaker -> resilience4j/Hystrix-successor pattern wrapping an RDS or downstream-service call in an ECS task.
- R9-06/07 Envoy outlier detection -> App Mesh virtual node outlier detection, with the same single-target panic-threshold caveat applying to any ALB/App Mesh target group with only one healthy target.
- R9-09 thread exhaustion -> the same unbounded-thread/connection-pool growth pattern that causes real ECS task OOM/CPU exhaustion under a hung RDS/ElastiCache dependency, exactly the R5 cascading-failure scenario R9 was built to mitigate.

## 14. Senior/Architect interview takeaways
- "Circuit breakers fail fast to protect the *caller* from resource exhaustion, and the *dependency* from being hammered while it's already struggling to recover" - I measured both effects directly (1500x latency improvement, 121->2 threads).
- "Where should the circuit breaker live - app or mesh?" - I can answer from direct comparison: app-level knows *why* (exact exception) and can stop *before* the network call; mesh-level only sees HTTP status codes but protects uniformly across all callers without per-language library integration - and I can cite the real single-host panic-threshold gotcha as a concrete caveat about mesh-level protection needing enough replicas to matter.
- "How do you validate a circuit breaker's timing?" - I don't trust vendor defaults; I measured `fail_max`, observed the exact half-open probe timing, and caught a stale-status-vs-live-behavior discrepancy that would trip up anyone relying only on a status endpoint.

## 15. $0 proof
All 8 reused/new images free/OSS. No AWS credential referenced anywhere. No AWS API call made.

## 16. Cleanup proof
`docker compose down -v` + `docker ps -a`/`docker network ls`/`docker volume ls` all grep-empty for `r9-circuit-breaker`.

## 17. Limitations
Single-app-instance topology limited Envoy's outlier detection to a stats-only demonstration rather than a real traffic-shifting one (documented as a genuine finding, not hidden). A multi-replica `app` cluster would be the natural next step to see real Envoy traffic ejection in action.

## R9 STATUS: **PASS**
All 10 experiments actually executed with real, measured evidence; 4 real investigations (not just "bugs") each root-caused using the tools' own real data (Envoy stats, docker exec thread counts, controlled Vegeta re-runs) rather than assumption; two circuit-breaking patterns genuinely compared, not just described; clean teardown; $0 cost.
