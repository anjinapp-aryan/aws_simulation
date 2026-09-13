# R6 — Proposed Architecture (pending approval, nothing built yet)

## Flow: existing project → reuse chain → runnable lab
```
EXISTING PROJECT               REUSE/ADAPT              R1-R5 COMPONENT           MINIMAL NEW GLUE
-----------------               -----------              ----------------          -----------------
valkey-io/valkey        --> REUSE (real cache engine, --                        --
                              BSD-3, wire-compat with
                              Redis, Sentinel included)
oliver006/redis_exporter --> REUSE (metrics)      --> feeds R4/R5's Prometheus  --
joeferner/redis-commander--> REUSE (key/TTL UI)    --                            --
Toxiproxy (Shopify)      --> REUSE, unchanged      --> same control API used     new proxy entry only
                                                       in R4/R5 (latency/cut)     (target: valkey:6379)
Traefik / Grafana /      --> REUSE, unchanged      --> identical containers/     --
Prometheus / Dozzle                                    config from R4/R5
Vegeta                   --> REUSE, unchanged      --> same one-off container    --
                                                       pattern from R5
labs/r4-rds/app/server.py --> ADAPT (minimal)      --> starting point            +1 endpoint (~25-30
                                                                                   lines): /cached-item
```
Everything above the last row is an unmodified reused image. The only new code is one endpoint on the already-existing app.

## Target topology
```
Client
  |
  v
Traefik (reused, file-provider mode, R2/R3/R5 pattern)
  |
  v
app (R4/R5's server.py + new /cached-item, cache-aside)
  |         \
  v          v
Valkey     PgBouncer -> Postgres (reused, unchanged from R4/R5)
(primary
 + 1 replica
 + 1 sentinel)
  ^
Toxiproxy (reused - new proxy: valkey-proxy -> valkey:6379)

Observability (all reused):
  redis_exporter -> Prometheus -> Grafana (hit/miss ratio, memory, replication offset)
  postgres_exporter -> Prometheus -> Grafana (carried from R4/R5, shows DB-load spikes during cache-miss/stampede)
  app logs -> Dozzle
Visualization: redis-commander (key/TTL browser)
```

## Why this shape (smallest useful)
- One Valkey primary + one replica + one Sentinel is the minimum topology that produces a **real** automatic failover (Sentinel actually promotes the replica) - fewer nodes than a production ElastiCache replication group, documented as a fidelity gap in the audit, not hidden.
- Toxiproxy sits in front of Valkey exactly the way it already sits in front of Postgres in R4/R5 - same mechanism, new target, zero new fault-injection code.
- The app gets exactly one new endpoint. No new framework, no cache library beyond the official `redis-py` client (also usable against Valkey - same wire protocol).

## Experiments mapped to architecture
R6-01 baseline hit/miss, R6-02 cold cache, R6-03 cache dependency down (Toxiproxy cut on valkey-proxy) - **the one genuinely open-ended troubleshooting experiment**, whether the app fails open or hard is not assumed in advance, R6-04 latency (Toxiproxy latency toxic on valkey-proxy), R6-05 stampede (Vegeta hammering one hot key at the instant its TTL expires), R6-06 primary/replica failover (kill the Valkey primary container, observe Sentinel promote the replica, observe whether the app reconnects).

## Custom code estimate
~25-30 lines total (`/cached-item` handler). Everything else is configuration for reused images (Sentinel config file, Toxiproxy API calls, Prometheus scrape target, Grafana datasource - all copy-adapted from R4/R5's existing files).

## REAL vs BEHAVIOR-EQUIVALENT vs NOT POSSIBLE (architecture-level)
- **REAL**: Valkey process, TCP connections, actual cache reads/writes, actual replication stream, actual Sentinel election/promotion, actual network latency via Toxiproxy, actual application exceptions on cache failure.
- **BEHAVIOR-EQUIVALENT**: this single-primary/single-replica/single-sentinel topology standing in for an ElastiCache replication group; Docker container kill standing in for an ElastiCache node failure.
- **NOT POSSIBLE LOCALLY**: AWS ElastiCache's own control plane, its DNS/endpoint cutover mechanics during failover, CloudWatch's native ElastiCache metrics, real Multi-AZ network partition behavior.

## $0 proof (architecture-level)
Every image above is free/self-hosted OSS (Valkey BSD-3, redis_exporter/redis-commander MIT, Toxiproxy/Traefik/Prometheus/Grafana/Dozzle already verified free in R2-R5). No AWS SDK call, no AWS credential referenced anywhere in the proposed compose file or scripts. Teardown will follow the identical `docker compose down -v` + `docker ps/network/volume ls` verification used in R4/R5.

## What will NOT be built
No custom cache-browser UI, no Redis Cluster/sharding, no AWS ElastiCache API mock, no more than one Sentinel.

---

Waiting for **"R6 ARCHITECTURE APPROVED"** before writing any docker-compose.yml, scripts, or app code.
