# R4 GitHub Reuse Audit — RDS/Database Connectivity Simulation

## What R4 should teach
The next unaddressed layer in the target architecture (ALB→ECS covered in R2/R3): real database connectivity failure modes — credential rejection, connection-pool exhaustion, network-level latency/unavailability — and how they map to production RDS troubleshooting.

## Search queries run this turn (real results, not assumed)
`rds local simulation chaos docker` → **0 results**, same negative-evidence pattern as every prior audit (Phase-Audit, R1, R2, R3). No integrated tool exists; components compose.

## Candidates evaluated

| Repo | Stars | License | Last push | Capability | Verdict |
|---|---|---|---|---|---|
| Shopify/toxiproxy | 12,330 | MIT | 2026-09-01 | Real TCP proxy for network-fault injection (latency, timeout, connection cut, bandwidth) — purpose-built for exactly this | **REUSE** — sits between app and Postgres |
| pgbouncer/pgbouncer | 4,354 | NOASSERTION ⚠️ | 2026-09-03 | Real PostgreSQL connection pooler — real `max_client_conn` enforcement, real "too many connections" rejection | **REUSE, license caveat**: NOASSERTION means GitHub couldn't classify it; PgBouncer is historically ISC-licensed per its own docs — worth a quick manual check of the actual LICENSE file before use, flagged not blocking |
| prometheus-community/postgres_exporter | 3,611 | Apache-2.0 | 2026-09-09 | Real Postgres metrics (connection count, query stats) for Prometheus | **REUSE** — extends the Prometheus/Grafana stack already decided in `phase-audit/HANDS-ON-PLATFORM-AUDIT.md` |
| sosedoff/pgweb | 9,499 | MIT | 2026-07-26 | Lightweight web UI, real query browser + connection view | **REUSE** for DB-state visualization — lighter than DBeaver (desktop-only, wrong fit for a headless Docker lab) |
| dbeaver/dbeaver | 51,729 | Apache-2.0 | active | Desktop DB client | **DO NOT USE** — not a fit for a containerized, agent-drivable lab despite the highest star count here; confirms stars aren't the criterion |
| Postgres's own `pgbench` (ships in `postgres:*` images) | — | PostgreSQL license | — | Real connection-load generator, official tool | **REUSE** for the pool-exhaustion experiment — avoids writing any custom load-generation code |

## Decision hierarchy applied

| Need | Decision | Mechanism |
|---|---|---|
| Real Postgres instance (RDS-equivalent) | **REUSE** | Official `postgres:16-alpine` image |
| Connection pool exhaustion | **REUSE** | pgbouncer with a deliberately low `max_client_conn`, real `pgbench -c N` load |
| Network-level failure (latency/timeout/cut) | **REUSE** | Toxiproxy sitting between app and Postgres, controlled via its real HTTP API / `toxiproxy-cli` |
| Metrics (RDS CloudWatch-equivalent) | **REUSE** | postgres_exporter → Prometheus → Grafana (same stack decided for R3's deferred observability layer) |
| DB-state visualization | **REUSE** | pgweb |
| App DB-calling endpoint | **ADAPT** | Extend the same tiny Python app pattern from R2/R3 (`app/server.py`) with one `/db` endpoint (psycopg2) — no existing tiny demo app both self-identifies *and* queries Postgres *and* has the independent health-toggle already proven useful; smallest coherent extension of an already-reused asset |
| Credential-failure scenario | **REUSE (Postgres's own auth)** | Real wrong password against real `pg_hba.conf` enforcement — zero code, real Postgres error text |

## Estimated custom code
~25-30 lines: one `/db` endpoint added to the existing app (mirrors the `/oom`/`/crash` additions already made in R3). No load generator, no chaos engine, no dashboard — all three reused whole.

## Real-vs-simulated boundary (proposed, to be verified on execution)
| AWS capability | Local simulation | Fidelity |
|---|---|---|
| RDS instance | Real Postgres container | Behavioral — real engine, not AWS-managed |
| Connection pool exhaustion | Real pgbouncer limit + real pgbench load | High — same failure class as `too many connections` on real RDS |
| Network path degradation (cross-AZ latency, packet loss) | Real Toxiproxy-injected latency/cut | High behavioral — real TCP-level fault, not AWS's specific network fabric |
| RDS Multi-AZ failover | **NOT REPRODUCIBLE LOCALLY** — no local equivalent of RDS's managed failover orchestration | Deferred to real-AWS CHEAP_MODE lab, per the standing project rule |
| CloudWatch RDS metrics | postgres_exporter + Prometheus + Grafana | Behavioral — real metrics, different product |

## $0 cost analysis
All 6 components (Postgres, pgbouncer, Toxiproxy, postgres_exporter, Prometheus, Grafana, pgweb) are free, open-source, self-hosted Docker images. No AWS account, no credentials, no paid tier of anything. Consistent with R1/R2/R3.

## Proposed architecture
```
app (extended r3-ecs pattern, /db endpoint)
   |
Toxiproxy (fault injection point)
   |
pgbouncer (connection pooling, exhaustion point)
   |
Postgres (real RDS-equivalent)
   |
postgres_exporter --> Prometheus --> Grafana (dashboard)
pgweb (ad-hoc DB visualization)
```

## Proposed experiment list (to be executed for real, not predicted)
| ID | Scenario | Real mechanism |
|---|---|---|
| R4-01 | Normal connectivity | `/db` query succeeds through the full chain |
| R4-02 | Credential failure | Wrong password → real Postgres auth rejection |
| R4-03 | Connection pool exhaustion | `pgbench -c N` against a tightened pgbouncer `max_client_conn`, observe real rejection + Grafana connection-count spike |
| R4-04 | Network latency injection | Toxiproxy `latency` toxic, observe real slow queries |
| R4-05 | Network cut (DB unreachable) | Toxiproxy `timeout`/disable, observe real connection failure, then re-enable and verify recovery |

## Stop conditions checked
- Reuse audit: complete, evidenced above.
- Better existing repo not evaluated: none found beyond the six listed; DBeaver considered and rejected with reason.
- Visualization considered: yes — Grafana (metrics) + pgweb (DB state), both reused, no custom UI.
- Architecture clarity: diagram above, consistent with R1-R3's proven compose-based pattern.
- Unnecessary custom code: none — single small endpoint addition, same pattern already used twice.
- AWS cost: $0, no real infrastructure proposed.

**Awaiting approval before implementation, per the stop condition.**
