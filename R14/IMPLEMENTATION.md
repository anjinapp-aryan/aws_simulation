# R14 — Implementation

## Step 1 — Inspection / reuse assessment (done before any build)
- App pattern: R4's `server.py` (minimal `ThreadingHTTPServer` + `psycopg2`, no ORM, no custom pool) — reused as the base, adapted to point at Patroni's HAProxy endpoint instead of PgBouncer, with `/write`, `/read`, `/read-replica`, `/whoami` added (all thin, no new mechanism).
- Visualization pattern: pgweb + Dozzle (R4/R11), Grafana/Prometheus (R4/R6/R9) — reused unmodified where used.
- Fault-injection pattern: R13's `inject.sh`/`evidence/`/timestamp-diffing convention — reused for RTO/RPO measurement scripts.
- Decision: **do not build a new HA/DR mechanism.** Reuse `patroni/patroni`'s own official demo (`docker-compose.yml` + `Dockerfile` + `docker/` in its repo) verbatim as the HA foundation — this is the smallest, most faithful extension possible; R14 adds only an app + visualization layer on top via `docker-compose.override.yml` joined to Patroni's own real Docker network, never editing the reused project's own files except where a real, documented bug required it (below).

## Step 2 — Build
`labs/r14-ha-dr/patroni-src/` — shallow clone of `patroni/patroni` (MIT), image built from its own `Dockerfile`, its own official `docker-compose.yml` run unmodified (3x Postgres+Patroni, 3x etcd, 1x HAProxy).
`labs/r14-ha-dr/app/` — R4-derived app.
`labs/r14-ha-dr/docker-compose.override.yml` — adds `app`/`pgweb`/`dozzle`, joined to Patroni's own `patroni-src_demo` network via `external: true`.

## Real bug found and fixed before Experiment 1 could even start
**BUG**: `demo-patroni1` container exited immediately; `docker logs` showed `/entrypoint.sh: 2: : not found` / `Syntax error: word unexpected (expecting "in")`.
**SYMPTOM**: all containers crash-looped on startup.
**EVIDENCE**: `file docker/entrypoint.sh` → "POSIX shell script, ... with CRLF line terminators"; `cat -A` showed `^M$` (CR) at the end of every line, including the shebang (`#!/bin/sh^M`).
**ROOT CAUSE**: this Windows environment's global `git config core.autocrlf=true` converted the shell script's LF line endings to CRLF on checkout. The container's real `/bin/sh` (dash) chokes on a `case "$1" in\r` line — `\r` is not whitespace to dash, so it parses as part of the token, producing exactly "word unexpected (expecting 'in')".
**FIX**: `sed -i 's/\r$//'` on every directly-executed file affected: `docker/entrypoint.sh`, `docker/patroni.env`, `patroni.py`, `patronictl.py`, `patroni_raft_controller.py`, `postgres0.yml`, `postgres1.yml`, `postgres2.yml` (found incrementally — the fix for `entrypoint.sh` alone surfaced a second, identical bug in `patronictl.py`'s shebang: `env: 'python3\r': No such file or directory`).
**REGRESSION TEST**: rebuilt the image, brought the cluster back up, confirmed via `patronictl list` a healthy 3-node cluster (1 Leader, 2 Replicas, both `streaming` with `0` lag).
**LESSON**: this is the same class of Windows/Git-Bash environment quirk this project has hit repeatedly (`MSYS_NO_PATHCONV`, PATH translation, `/dev/tcp`) — now extended to "never assume a freshly `git clone`d third-party repo's shell/Python scripts survived a Windows checkout intact; check line endings before debugging application logic."

## Step 3 — Experiment 1 executed (see `R14/EXPERIMENT-RESULTS.md`)
