# R14 — Metrics Visualization (Patroni HA/DR)

Optional, additive Prometheus + Grafana visualization layer for R14. Zero edits to `patroni-src/` (official, unmodified) or `docker-compose.override.yml` (`app`/`pgweb`/`dozzle`, unchanged). All new files live under `labs/r14-ha-dr/monitoring/` + one new `docker-compose.monitoring.yml`.

## 1. Why this was added
R14's `docker-compose.override.yml` had zero metrics infrastructure — HA state, replication lag, and failover were only ever visible via `patronictl list` text output or the app's own `/whoami` endpoint (confirmed by reading the file directly: exactly 3 services, `app`/`pgweb`/`dozzle`, none of them Prometheus/Grafana). This was the single most-evidenced remaining gap across all 15 phases (see `R1-R15-VISUALIZATION-AUDIT.md`).

## 2. Real topology inspected before assuming architecture
Read `patroni-src/docker-compose.yml` directly: 3 Postgres+Patroni nodes (`patroni1`/`patroni2`/`patroni3`, real hostnames on the `demo` Docker network), 3 etcd nodes, 1 HAProxy (host ports `5000`=write/`5001`=read). Read `docker/patroni.env`: REST API credentials `admin`/`admin`.

## 3. GitHub/native-API reuse audit and architecture decision
**Investigated whether Patroni itself exposes `/metrics` before defaulting to `postgres_exporter`-only, per the task's own instruction to prefer it if available.** Read `patroni-src/patroni/api.py` (`do_GET_metrics`) — confirmed real: Patroni ships a native, built-in `/metrics` REST endpoint on port 8008 of every node, in real Prometheus exposition format, with authoritative HA-state fields no generic Postgres exporter can produce: `patroni_primary`, `patroni_replica`, `patroni_standby_leader`, `patroni_xlog_location`, `patroni_xlog_replayed_location`, `patroni_postgres_running`, `patroni_postmaster_start_time`, etc.

**Live-tested auth requirement** (this session): `curl http://localhost:8008/metrics` from inside `patroni1` returned `HTTP 200` **with no credentials at all** — Patroni's `/metrics` endpoint is unauthenticated by design (unlike the rest of its REST API).

**Decision: two-source architecture, not exporter-only:**
| Source | Role | Reasoning |
|---|---|---|
| Patroni's own `/metrics` (all 3 nodes, `patroni1:8008`/`patroni2:8008`/`patroni3:8008`) | **PRIMARY** — HA state, replication, failover | Authoritative — comes directly from the process making the HA decisions, not inferred. Zero new dependency (no exporter to install). Real, live-verified. |
| `postgres_exporter` (prometheus-community, same image already used in R4) against **HAProxy's write port** (`haproxy:5000`) | **SECONDARY** — connection count, `pg_up` | Standard Postgres metrics Patroni's endpoint doesn't carry; scraping through HAProxy (not a fixed node) means it always reflects whoever the *real current leader* is, without reconfiguring on failover. |

**Multi-node decision**: Patroni is scraped per-node (3 targets) — this is what lets the dashboard show role transitions (which node is primary) rather than a single pre-selected target. `postgres_exporter` is a single instance pointed at HAProxy's write port, not one per node — the "Active Connections" panel is only meaningful for the current leader, and HAProxy already resolves that in real time; three separate exporters would triple the panel count for no added signal in a learning-lab dashboard that is meant to stay small.

## 4. Dashboard reuse audit
Searched grafana.com for existing Patroni dashboards. Found **ID 18870 ("PostgreSQL Patroni")**, built specifically to consume Patroni's own `/metrics` fields — strong field-level match confirming the metric selection above is the right one. **Not imported verbatim**: its panels are template-variabled on `$service_name`/`$scope_name` (PMM/Percona-ecosystem label conventions) that don't match this project's actual scrape labels (`scope="demo"`, `name="patroni1"`, confirmed via live query in step 3) — forcing the import would produce panels with unresolvable variables. **Used as REFERENCE, not REUSE**: it validated which Patroni metrics matter and confirmed the field names; the actual dashboard JSON (`monitoring/grafana/dashboards/r14-patroni-ha.json`) was hand-built directly against this project's real labels, following R4/R6's existing datasource-provisioning pattern (no prior lab had needed dashboard-JSON provisioning, so `monitoring/grafana/provisioning/dashboards/dashboard.yml` — a standard Grafana file-provider config — is new).

## 5. What was built
- `labs/r14-ha-dr/docker-compose.monitoring.yml` — new, additive compose file joining Patroni's real `demo` network (`external: true`, same pattern as `docker-compose.override.yml`): `postgres_exporter`, `prometheus`, `grafana`.
- `labs/r14-ha-dr/monitoring/prometheus/prometheus.yml` — scrapes `patroni1/2/3:8008` (`metrics_path: /metrics`) + `postgres_exporter:9187`. Same shape as R4/R6's own `prometheus.yml`.
- `labs/r14-ha-dr/monitoring/grafana/provisioning/datasources/prometheus.yml` — identical to R4/R6's datasource file.
- `labs/r14-ha-dr/monitoring/grafana/provisioning/dashboards/dashboard.yml` + `monitoring/grafana/dashboards/r14-patroni-ha.json` — 5 panels: **Primary/Replica State**, **Replication Lag**, **WAL Replay Activity**, **Active Connections**, **PostgreSQL Availability**. Every panel's PromQL query was live-tested against the running cluster before being written into the JSON (see step 6).

Ports: Prometheus `58503`, Grafana `58504` (following R14's existing `585xx` host-port convention from `docker-compose.override.yml`).

## 6. Live panel verification (OBSERVED, this session)
```
patroni_primary                                    -> patroni1=0, patroni2=0, patroni3=1   (matches patronictl list)
pg_stat_database_numbackends{datname="postgres"}    -> 4                                     (real postgres_exporter metric name, confirmed live)
pg_up                                               -> 1
```
**Real bug found while building panel 2** ("Replication Lag"): `max(patroni_xlog_location) - patroni_xlog_replayed_location` returned an empty result set — Prometheus vector-matching requires identical label sets, and `max()` with no `by()` strips all labels. Fixed with `scalar(max(patroni_xlog_location)) - patroni_xlog_replayed_location`. **Second issue found**: the corrected query showed a large, meaningless "lag" value on the *leader's own row* (leader's `xlog_replayed_location` is 0, since it isn't replaying anything) — fixed by zeroing non-replica rows: `(scalar(max(patroni_xlog_location)) - patroni_xlog_replayed_location) * on(name) group_left() patroni_replica`. Live-verified: replicas showed real (`0`, cluster idle) lag; the leader's row showed `0` via the multiply-by-role-flag, not a spurious huge number.

## 7. Failure/recovery observation — reused R14's own Experiment 3 mechanism
Per the task's instruction not to invent a new failure mechanism, this reused **R14's proven "real leader kill and measured automatic failover"** experiment (`docker kill demo-<leader>`, the exact mechanism from `R14/EXPERIMENT-RESULTS.md` Experiment 3), observed through the new dashboards instead of `patronictl list`:

**Run 1** — `docker kill demo-patroni3` at `T0=14:25:01.238`. Dashboard's `patroni_primary` query showed patroni3 drop out at `14:25:08`, and **patroni1 become the new `=1` row at `14:25:29`** — a real, dashboard-observed failover in ~28s, consistent with the prior lab's independently-measured 26.26s RTO (same DCS-lease-TTL mechanism, not a coincidence).

**Full data**: `labs/r14-ha-dr/evidence/metrics-viz/failover-through-dashboards.log`.

### Real bug found during this experiment (investigated, not hidden)
`pg_up` went to `no-data` at the moment of the kill and **never recovered on its own** — even minutes after the new leader (`patroni1`) was confirmed healthy and directly reachable (`psql` through HAProxy succeeded immediately). Investigation:
- `postgres_exporter` logs: `driver: bad connection` → reconnect attempt → `error querying postgresql version: EOF`, then silence.
- Prometheus's own target health: `down`, `"Get .../metrics": context deadline exceeded`.
- A direct `wget` to the exporter's own `/metrics` endpoint hung with no response at all.

**Root cause**: the exporter's cached DB connection pointed at a now-dead socket (the killed leader container); its reconnect attempt had no `connect_timeout` on the DSN, so it could hang indefinitely inside the `/metrics` handler itself — even though HAProxy had already correctly rerouted and the database was genuinely healthy and reachable. A manual `docker compose restart postgres_exporter` cleared it instantly, confirming the DB/network side was never actually broken — only the exporter's own connection handling was.

**Fix**: added `connect_timeout=5` to the exporter's DSN, plus a Docker `healthcheck` (visibility only — a plain healthcheck does not auto-restart a container without an orchestrator or a watcher like `willfarrell/autoheal`, deliberately not added to keep this $0/minimal; documented rather than overclaimed).

**Run 2 (re-test with the fix)** — `docker kill demo-patroni1` (now the leader) at `T0=14:28:22.843`. This time: `pg_up` went to a real, bounded `0` at `14:28:47` (not `no-data`), patroni2 became the new leader at `14:28:54`, and **`pg_up` self-recovered to `1` at `14:28:57` — automatically, with no manual restart.** Full before/after evidence in the same log file, both runs.

## 8. Explicit non-conflation (per task requirement)
- **Replication lag ≠ RPO.** The "Replication Lag" panel shows live WAL byte lag from Patroni's own metrics — a real-time signal, not a recovery-point guarantee. The lab's actual RPO methodology (which measures real committed-row loss across a genuine network partition) is `R14/RTO-RPO.md`, unchanged and unreplaced by this dashboard — the dashboard panel description says so explicitly.
- **Grafana ≠ CloudWatch, local Patroni ≠ real RDS Multi-AZ.** No panel or doc in this addition claims AWS-console equivalence; see AWS mapping below.

## 9. AWS mapping
```
Patroni /metrics + postgres_exporter -> Prometheus -> Grafana
CloudWatch RDS Multi-AZ metrics (ReplicaLag, DatabaseConnections, FailoverStatus) -> CloudWatch -> CloudWatch Dashboards
```
**Classification: CONCEPTUAL MAPPING / BEHAVIOR-EQUIVALENT.** Same *category* of signal (replication lag, connection count, availability, failover event) a real RDS Multi-AZ operator would watch in CloudWatch — not a reproduction of CloudWatch's own metric names, aggregation windows, or console. Local Patroni's async-by-default replication and this lab's own measured RPO (32 real rows lost in a genuine partition, per `R14/EXPERIMENT-RESULTS.md`) is explicitly **not** RDS Multi-AZ's synchronous, RPO=0-by-design behavior — the dashboard observes real local behavior, it does not simulate RDS's stronger guarantee.

## 10. $0 validation
`prom/prometheus`, `grafana/grafana`, `prometheuscommunity/postgres-exporter` — all free, unauthenticated public images, same as R4/R6's existing stack. No AWS resource, account, or credential referenced anywhere.

## 11. Regression results (OBSERVED, live, this session)
| Check | Result |
|---|---|
| `patronictl list` after 2 real leader kills | Healthy, `patroni2` Leader, `TL=3` (correctly incremented twice) |
| App (`:58500/whoami`) | `HTTP 200` |
| pgweb (`:58501`) | `HTTP 200` |
| Dozzle (`:58502`) | `HTTP 200` |
| `git status` | Only new files under `labs/r14-ha-dr/` + this report; zero existing files modified anywhere in the repo |

## 12. Files changed/created
- **Created**: `labs/r14-ha-dr/docker-compose.monitoring.yml`, `labs/r14-ha-dr/monitoring/prometheus/prometheus.yml`, `labs/r14-ha-dr/monitoring/grafana/provisioning/datasources/prometheus.yml`, `labs/r14-ha-dr/monitoring/grafana/provisioning/dashboards/dashboard.yml`, `labs/r14-ha-dr/monitoring/grafana/dashboards/r14-patroni-ha.json`, `labs/r14-ha-dr/evidence/metrics-viz/failover-through-dashboards.log`, this file.
- **Not changed**: `patroni-src/*` (official, untouched), `docker-compose.override.yml`, any script, any other R-phase.

## 13. Commands
**Start** (after Patroni's own stack is already up, per R14's existing instructions):
```bash
cd labs/r14-ha-dr
docker compose -f docker-compose.monitoring.yml up -d
# Prometheus: http://localhost:58503   Grafana: http://localhost:58504 (anonymous Viewer access, dashboard "R14 - Patroni HA/DR" auto-provisioned)
```
**Rollback** (remove monitoring entirely, R14's HA/DR mechanism and all other tools continue exactly as before):
```bash
docker compose -f docker-compose.monitoring.yml down
```
Verified: the HA/DR mechanism itself (`patroni-src`), failover, backup/restore, `app`, `pgweb`, and `dozzle` have zero dependency on this monitoring layer and are unaffected by either its presence or its removal.

## 14. Senior-architect interview takeaway
"We added Patroni's own native `/metrics` as the primary HA-state source instead of defaulting to a generic Postgres exporter, because the process making the failover decision is also the most authoritative place to observe it from — and while building the dashboard we hit a real failure mode that generic exporters have in production too: a connection-pooled exporter can itself go silently unresponsive right at the moment of a failover, because its cached socket dies with the old leader and a reconnect with no timeout can hang indefinitely. We only found that because we watched the dashboard through a real `docker kill`, not because we assumed the happy path — the first run showed the exporter stuck on `no-data` forever; after adding `connect_timeout`, the second run showed the same failure recover automatically in under 10 seconds. That's the same class of blind spot that catches real monitoring stacks off guard during real RDS failovers."
