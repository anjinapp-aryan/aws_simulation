# R6 Reuse Audit — Caching Layer (ElastiCache-equivalent) Failure & Failover

## 1. R6 learning objective
Experience how a real caching tier (AWS ElastiCache for Redis/Valkey) behaves under normal load, cache-miss stampede, node failure, and primary/replica failover — and how an application should (and shouldn't) degrade when its cache dependency dies.

## 2. What's already covered by R1-R5
R1 IAM/task-identity, R2 ALB/health-check routing, R3 ECS/ECR/Fargate lifecycle (OOM, crash, restart), R4 RDS connectivity (auth, pool exhaustion, latency, cut), R5 observability + CPU/memory pressure + backend failure + cascading DB→health→routing failure.

## 3. Remaining hands-on gap
Nothing in R1-R5 touches a **caching tier** or **primary/replica automatic failover** — two of the most commonly asked Lead/Architect AWS topics (cache-aside pattern, cache stampede/thundering herd, ElastiCache Multi-AZ failover, graceful degradation when a dependency is down). This is the clearest remaining gap.

## 4/5/6. GitHub reuse search + candidates

Real searches run (GitHub Search API, live results):

| Query | Result |
|---|---|
| `redis local elasticache simulation docker` | 0 results |
| `redis chaos failover docker` | 0 results |
| `elasticache local simulation` | 0 results |
| `redis sentinel docker compose` | 81 results, nothing integrated/maintained enough to reuse wholesale (top hit 474★, last pushed 2023) |

Consistent with every prior audit: no integrated "AWS caching simulator" exists. Compose mature standalone projects instead.

| Repo | Stars | License | Last push | Capability | Decision |
|---|---|---|---|---|---|
| `redis/redis` | 76,330 | **Mixed** — ≤7.2 is BSD-3-Clause; Redis 8+/current is tri-licensed (RSALv2/SSPLv1/AGPLv3), confirmed by reading the actual `LICENSE.txt`, not the GitHub UI badge | 2026-09-10, active | The real cache engine | **REJECT current version** — license change makes it a worse fit for a "reuse permissively-licensed tools" project than the alternative below |
| `valkey-io/valkey` | 27,175 | BSD-3-Clause (verified) | 2026-09-11, active | Linux Foundation fork of Redis 7.2, wire-protocol compatible, same commands/Sentinel/replication | **REUSE** — same real cache behavior, cleanly permissive license. Notable real-world parallel: AWS ElastiCache itself now offers a "Valkey" engine option alongside Redis OSS, so this is not a stretch substitution, it's the same choice AWS gives customers |
| `oliver006/redis_exporter` | 3,688 | MIT | 2026-09-07, active | Prometheus exporter: hit/miss ratio, memory, connected clients, replication state | **REUSE** — same pattern as R4's postgres_exporter |
| `joeferner/redis-commander` | 4,003 | MIT | 2026-02-12, active | Web UI to browse keys/TTLs, real GitHub project (not custom-built) | **REUSE** — real visualization, avoids building a custom key browser |
| Toxiproxy (Shopify) | — | MIT | — | Real TCP fault injection | **REUSE, carried forward unchanged from R4/R5** — same mechanism, new target (cache port instead of DB port) |
| Traefik / Prometheus / Grafana / Dozzle | — | — | — | Routing/dashboard/logs, already proven | **REUSE, carried forward unchanged** |
| Vegeta | — | MIT | — | HTTP load, already proven in R5 | **REUSE, carried forward unchanged** — needed for the cache-stampede experiment |

## 7. Visualization
redis-commander (key/TTL browser, real tool) + Grafana panel fed by redis_exporter (hit/miss ratio, memory, connected clients, `master_repl_offset` for replication lag) + Traefik/Dozzle carried forward. No custom UI.

## 8. Proposed architecture (smallest useful)
```
Client -> Traefik -> app (extends R4/R5's app: one new /cached-item endpoint,
                            cache-aside pattern)
                        |         |
                        v         v
                     Valkey    Postgres (via PgBouncer, reused from R4)
                   (primary +
                    1 replica +
                    1 sentinel)
                        ^
                   Toxiproxy (reused - new proxy on the Valkey port)

valkey/redis_exporter -> Prometheus -> Grafana
redis-commander (key browser)
```
Single sentinel is enough to demonstrate real failover locally (production ElastiCache uses more nodes for quorum; documented as a fidelity gap, not hidden).

## 9. Experiments (progressive difficulty)

| # | Experiment | Break mechanism | AWS mapping |
|---|---|---|---|
| R6-01 | Baseline cache-aside | none — warm cache, fast responses | Normal ElastiCache-backed request path |
| R6-02 | Cold cache / cache miss | flush Valkey keys | First-request-after-deploy or TTL-expiry latency spike, real DB load increase (visible via R4/R5's existing Postgres Grafana panel) |
| R6-03 | Cache dependency down | Toxiproxy cuts Valkey connectivity | ElastiCache node/AZ unreachable — tests whether the app fails open (degrades to DB) or fails hard; **this is the one experiment that requires real troubleshooting**, not just observing an expected failure |
| R6-04 | Cache stampede | Vegeta fires concurrent load at the instant a hot key expires | Thundering-herd on cache-miss, classic interview scenario, real DB connection/latency spike |
| R6-05 | Primary/replica failover | kill the Valkey primary container | ElastiCache Multi-AZ automatic failover — Sentinel promotes replica, app must reconnect to the new primary |

Each experiment follows START→BASELINE→OBSERVE→BREAK→OBSERVE FAILURE→DIAGNOSE→FIX→VERIFY→MAP TO AWS, with a short "what I can now explain in an interview" note, no theory dump.

## 10. REAL vs BEHAVIOR-EQUIVALENT vs AWS-ONLY

| | REAL | BEHAVIOR-EQUIVALENT | AWS-ONLY |
|---|---|---|---|
| Cache-aside latency difference | Real Valkey vs real Postgres query timing | — | — |
| Cache-miss DB load spike | Real Postgres connection/query load | — | — |
| Toxiproxy cache-cut / app degradation | Real TCP failure, real app exception handling | ElastiCache node failure | AWS's own health-check/replacement timing |
| Sentinel primary/replica failover | Real Valkey replication + real Sentinel promotion | ElastiCache Multi-AZ automatic failover (mechanism, not the same control plane) | Actual ElastiCache failover DNS/endpoint update, CloudWatch failover events |
| Cache stampede | Real concurrent misses, real DB spike (Vegeta-driven) | — | — |

## 11. Estimated custom code
One new endpoint in the existing app (`/cached-item`, ~25-30 lines: check Valkey, on miss query Postgres and populate cache with TTL) — same sizing discipline as every prior phase's single-endpoint additions. No new services beyond the reused images above.

## 12. Zero-cost proof strategy
Same as R1-R5: no AWS credential file present or referenced, all images free/self-hosted (Valkey, redis_exporter, redis-commander all free OSS), `docker compose down -v` + `docker ps/network ls/volume ls` grep-empty verification at teardown.

## 13. What will NOT be built
No custom cache-browsing UI (redis-commander covers it). No Redis Cluster (sharding) - out of scope, single-primary+replica is enough to teach failover; noted as a fidelity gap. No AWS ElastiCache API mocking (would be fake, not real behavior).

## 14. Implementation plan (after approval)
`labs/r6-caching/` mirroring R4/R5's layout: `docker-compose.yml`, `app/` (extend R4/R5's server.py with `/cached-item`), `redis-sentinel/` config, `prometheus/`, `grafana/`, `scripts/` (run, status, cache-flush, break-cache-cut, stampede, kill-primary, fix, verify, cleanup), `evidence/R6-01..05/`.

## 15. Approval gate
STOPPING HERE. No docker-compose.yml, scripts, or app code will be written until you say **"R6 ARCHITECTURE APPROVED."**
