# R5 — Observability / Resource Pressure — Forensic Audit

## A. Objective
Demonstrate real CPU/memory pressure, real OOM behavior, and real observability (metrics/logs/dashboards) of resource impact — including honestly documenting any tool that doesn't work in this environment rather than asserting it does.

## B. Implementation — WHERE IS IT
| Mechanism | File/path | Purpose |
|---|---|---|
| Full app stack | `docker-compose.yml` (Traefik, app, postgres, pgbouncer, toxiproxy, postgres_exporter — the R4 stack, reused) | Base system under pressure |
| Per-container metrics | `docker-compose.yml` service `cadvisor` (`gcr.io/cadvisor/cadvisor:v0.52.1`) | Real container-level CPU/mem metrics — **see current-state finding below** |
| Cluster/host metrics + dashboards | `prometheus`, `grafana` | Real time-series storage/visualization |
| Logs | `dozzle` | Real-time container logs |
| Stress tooling | `scripts/cpu-stress.sh`, `scripts/mem-stress.sh`, `scripts/_stage-stress-ng.sh` (stages the real `stress-ng` binary into the app container) | Real resource pressure, not simulated |
| Load generation | `scripts/load-vegeta.sh` (real `vegeta`) | Real HTTP load |
| Cascading-failure experiment | `scripts/cascading-failure.sh` | Chains DB degradation → app impact |

## C. Runnability — ACTUALLY EXECUTED THIS SESSION
`docker compose up -d --build`: **PASS**, clean start.

## D. Experiment Audit
| Experiment | Command | Failure injected | Actual evidence (live, this session) | Verification | Recovery | Reproducibility |
|---|---|---|---|---|---|---|
| cAdvisor per-container metrics | `curl http://localhost:58082/api/v1.3/docker/` | none (baseline check) | **`{}`** — empty, zero containers reported, despite the container running and Prometheus successfully scraping the endpoint (`up{job="cadvisor"}=1`) | direct API response, cross-checked against Prometheus's own `up` metric | n/a — this is a standing, documented limitation, not a transient failure | **Confirmed, currently, still broken — exactly matching the project's own pre-existing `evidence/R5-01/cadvisor-bug-investigation.log`**, which already root-caused this to a Docker-API-version-negotiation incompatibility between cAdvisor's vendored client and this specific Docker Desktop daemon, tested across two cAdvisor versions and an explicit `DOCKER_API_VERSION` override, all failing identically. This is a genuine, already-honestly-documented gap, re-confirmed present today — a strong positive signal for this project's documentation integrity (the docs did not overstate cAdvisor's working state) |
| CPU pressure | `bash scripts/cpu-stress.sh 15 2` | real `stress-ng --cpu 2 --timeout 15s` inside the live app container | `docker stats`: **`r5-observability-app-1 200.27%`** CPU — real, measured, consistent with 2 stress workers | independent `docker stats` reading (the proven fallback mechanism, per the project's own documented cAdvisor workaround) | automatic (stress-ng's own timeout) | **GREEN** |
| Prometheus targets | `curl http://localhost:59090/api/v1/query?query=up` | none | `postgres 1`, `cadvisor 1` — both scrape targets reachable (cAdvisor's *endpoint* is up; its *per-container data* is empty, a real and important distinction) | direct API response | n/a | GREEN (target reachability), N/A (container-level data) |
| Memory pressure (`mem-stress.sh`) | not executed this session | — | **NOT RE-VERIFIED LIVE** — HISTORICALLY DOCUMENTED only (`evidence/R5-03/*.log`, including the project's own honest `bug-no-oom-first-attempt.log`) | — | — | **UNVERIFIED THIS SESSION** |
| Cascading failure (`cascading-failure.sh`) | not executed this session | — | **NOT RE-VERIFIED LIVE** — HISTORICALLY DOCUMENTED only (`evidence/R5-06/*.log`) | — | — | **UNVERIFIED THIS SESSION** |
| DB-latency-under-load (`break-db.sh` + `load-vegeta.sh`, R5-04/05) | not executed this session | — | **NOT RE-VERIFIED LIVE** — HISTORICALLY DOCUMENTED only (`evidence/R5-04/*.log`, `R5-05/*.log`) | — | — | **UNVERIFIED THIS SESSION** |

## E. Hands-on score
cAdvisor check: **7** (this is itself a root-cause investigation re-confirmed — the highest evidence tier, "unexpected issue root-caused," now independently re-verified as still accurate). CPU stress: **4** (failure/pressure injected and observed via an independent, real metric). Prometheus targets: **2** (implementation + runnable, no fault involved).

## R5-Specific Determination (per the required Step 8 format)
- CPU pressure: **REAL**, confirmed live this session.
- Memory pressure / OOM under R5's own scripts: HISTORICALLY DOCUMENTED (including an honestly-logged "bug, no OOM on first attempt" investigation — a good sign of rigor), **NOT re-verified live this session**.
- Application/DB/backend impact under load, cascading effects: HISTORICALLY DOCUMENTED, **NOT re-verified live this session**.
- Metrics: cAdvisor per-container metrics are **IMPLEMENTED BUT CURRENTLY BROKEN** (confirmed, real, root-caused, with a real, already-proven workaround — `docker stats`, the same mechanism used successfully in R3's own audit this session). Prometheus/Grafana/host-level metrics: REAL.
- Logs: Dozzle — implementation present, not independently re-verified live this session (no reason to doubt it, given R1-R4's consistent Dozzle behavior across this whole project, but per the audit's own "do not silently upgrade unverified claims" rule, this is recorded as UNVERIFIED THIS SESSION, not PASS).

## Score: 77/100
Implementation 15/15, Runnable 15/15, Real experiment 12/20 (only CPU pressure + the cAdvisor investigation independently re-verified live; 3 of the phase's ~5 documented experiment families were not re-executed this session, purely due to audit time constraints, not because anything is known to be broken), Failure injection 9/15 (real for CPU; unverified for memory/cascading/DB-latency this session), Observation 8/10, Independent verification 7/10, Recovery 3/5 (not exercised this session beyond stress-ng's own timeout), Reproducibility 4/5 (what WAS tested reproduced cleanly; what wasn't tested carries no negative evidence, just no positive evidence either), Documentation 4/5 (genuinely excellent, honest bug-investigation logs already present in the repo — a real strength).

## Historical vs. Current
**HISTORICALLY CLAIMED**: `R5-REPORT.md` and `evidence/R5-0{1..6}/*.log` claim PASS across 6 experiment families, including two genuinely honest, already-logged bug investigations (the cAdvisor incompatibility, and a first-attempt OOM miss later fixed).
**CURRENTLY VERIFIED**: cAdvisor's limitation **re-confirmed live, unchanged** — a rare case where re-testing a "known broken" claim actually validates the documentation's honesty rather than contradicting it. CPU pressure **independently re-verified live**. Memory pressure, cascading failure, and DB-latency-under-load experiments are **NOT currently re-verified** by this audit — they remain HISTORICALLY DOCUMENTED ONLY until someone re-runs them; this audit found no evidence they are broken, only that they were not re-checked in this session.
