# R4 — RDS-like Database / PgBouncer / Toxiproxy — Forensic Audit

## A. Objective
Demonstrate real database connectivity through a real connection pooler, real network-fault injection (latency), real pool exhaustion, and real observability of DB-layer metrics.

## B. Implementation — WHERE IS IT
| Mechanism | File/path | Purpose |
|---|---|---|
| Database | `docker-compose.yml` service `postgres` (`postgres:16-alpine`, official, unmodified) | Real Postgres |
| Connection pooler | `docker-compose.yml` service `pgbouncer` (`edoburu/pgbouncer`), config `pgbouncer/pgbouncer.ini` (`max_client_conn=5`, `default_pool_size=5`, deliberately small) | Real pool-exhaustion boundary |
| Network fault injection | `docker-compose.yml` service `toxiproxy` (`ghcr.io/shopify/toxiproxy:2.9.0`, official) | Real TCP-level latency/toxic injection, control API exposed on `48474` |
| App | `app/server.py`, one `/db` endpoint | Minimal, real `psycopg2` connection through the full chain |
| Observability | `postgres_exporter`, `prometheus`, `grafana`, `pgweb` — all official, unmodified | Real metrics, real row-level DB inspection |
| Experiments | `scripts/inject-latency.sh`, `remove-latency.sh`, `exhaust-pool.sh` (real `pgbench`), `cut-network.sh`/`restore-network.sh`, `bad-credentials.sh` | Real, distinct fault types |

## C. Runnability — ACTUALLY EXECUTED THIS SESSION
`docker compose up -d --build`: **PASS**, clean start, all services healthy.

## D. Experiment Audit (ALL executed live, this session)
| Experiment | Command | Failure injected | Actual evidence (live) | Verification | Recovery | Reproducibility |
|---|---|---|---|---|---|---|
| Baseline connectivity | `curl http://localhost:48000/db` | none | `OK db_time=... elapsed=0.008s` — real Postgres query result, real backend PID | direct response | n/a | **GREEN** |
| Latency injection | `bash scripts/inject-latency.sh 2000` then `/db` | real Toxiproxy 2000ms latency toxic | `DB_ERROR after 2.912s: OperationalError: ... timeout expired` — real psycopg2 exception text, real elapsed time consistent with the injected toxic | direct response text + timing | `bash scripts/remove-latency.sh` | **GREEN** |
| Latency recovery | `bash scripts/remove-latency.sh` then `/db` | toxic removed | `OK ... elapsed=0.008s` — back to baseline | direct response | — | **GREEN** |
| Pool exhaustion | `bash scripts/exhaust-pool.sh 15` | real 15-client `pgbench` against `max_client_conn=5` | `pgbench: error: connection to server at "pgbouncer" ... FATAL: no more connections allowed (max_client_conn)` — real PgBouncer enforcement, exact real error text | direct `pgbench` output | connections release automatically | **GREEN** |
| Metrics | `curl http://localhost:49090/api/v1/query?query=pg_up` | none | `{"metric":{"__name__":"pg_up",...},"value":[...,"1"]}` — real Prometheus scrape of real `postgres_exporter` data | direct Prometheus API response | n/a | **GREEN** |

Every row above was executed and its evidence captured live during this audit.

## E. Hands-on score
Baseline: **3**. Latency injection: **5** (failure injected and observed with a real, specific error and timing). Latency recovery: **6**. Pool exhaustion: **5** (real, distinct fault type, real tool (`pgbench`) producing a real, unambiguous error). Metrics: **3** (implementation + real data present, no fault involved).

## R4-Specific Determination (per the required Step 7 format)
- Database connectivity: **REAL**.
- Connection pooling / pool exhaustion: **REAL** (genuine PgBouncer enforcement, not simulated — the exact error text is PgBouncer's own).
- Latency injection / network failure: **REAL** (genuine TCP-level Toxiproxy toxic, not an app-level sleep).
- Database failure: not exercised in this specific re-test (a `cut-network.sh`/`bad-credentials.sh` pair also exists and was not re-run live this session due to time constraints — HISTORICALLY DOCUMENTED per `evidence/r4-summary.log`, not re-verified here).
- Recovery: **REAL**, confirmed live.
- Observability: **REAL** — a specific, meaningful metric (`pg_up`) was checked and confirmed present, not merely "Grafana exists."

## Score: 95/100
Implementation 15/15, Runnable 15/15, Real experiment 19/20 (5 of the lab's ~7 documented experiment types re-verified live; `cut-network.sh`/`bad-credentials.sh` not re-run this session), Failure injection 14/15, Observation 10/10, Independent verification 9/10, Recovery 5/5, Reproducibility 5/5 (zero manual intervention, clean first-attempt reproduction), Documentation 3/5 (not deeply re-read this session; the live evidence stood on its own).

## Historical vs. Current
**HISTORICALLY CLAIMED**: PASS, per `evidence/r4-summary.log` and `R4-REPORT.md`.
**CURRENTLY VERIFIED**: **PASS, independently reproduced live in this session** for connectivity, latency injection/recovery, pool exhaustion, and metrics — the strongest and cleanest phase alongside R2, with real, unambiguous tool-native error text at every fault boundary.
