# R3 GitHub Reuse Audit — ECR + ECS/Fargate Simulation

## Candidates evaluated (real data, checked this turn)

| Repo | Stars | License | Last push | Capability | Verdict |
|---|---|---|---|---|---|
| distribution/distribution | 10,611 | Apache-2.0 | 2026-09-02 | Docker's own official registry — real push/pull/storage, real image manifest lifecycle | **REUSE** as the ECR-equivalent |
| amir20/dozzle | 14,343 | MIT | 2026-09-11 (today) | Real-time container log viewer, zero-config, web UI | **REUSE** for Experiment 8 (logs) — directly answers "prefer a log viewer over reading raw files" |
| portainer/portainer | 38,484 | Zlib | 2026-09-10 | Real container state dashboard (RUNNING/STOPPED/restarting, resource usage) | **REUSE** — carried forward from the Phase-Audit decision, now put to direct use for task-state visualization |
| weaveworks/scope | 5,909 | Apache-2.0 | **2023-07 — 3+ years stale** | Topology viz | **DO NOT USE** — unchanged verdict from prior audits |
| traefik/traefik | 64,814+ | MIT | active | Reverse proxy + health checks + dashboard | **REUSE, carried forward from R2** |
| amazon/amazon-ecs-local-container-endpoints | 517 | Apache-2.0 | active enough | Real AWS-official task-role/metadata endpoint | **REUSE, carried forward from R1**, proven working |
| Targeted search "ecs fargate local simulation" | — | — | — | **Zero results** | Confirms — again — no integrated ECS-local-sim project exists. Components compose; nothing off-the-shelf does the whole thing. |

## Windows/Docker Desktop compatibility — checked against R2's known issue

R2 found that Traefik's **Docker-socket label-discovery** provider fails on this specific Windows/Docker-Desktop setup with a persistent empty-body daemon error (`"Error response from daemon: "`), and worked around it using Traefik's **file provider** instead (same real health checks/routing, static backend list). That workaround is **carried forward for R3**, with one addition needed for the scaling experiments (Experiment 9): the static file needs to be **regenerated** when desired-count changes, since file-provider mode has no auto-discovery. This is done via a small script that lists running `app` containers (`docker compose ps --format`) and rewrites `traefik-dynamic.yml` accordingly — a real, honest reconciliation mechanism (not a scheduler clone), triggered manually by the scale script, not automatic like real ECS. **Documented as a fidelity limitation up front, not discovered later.**

`distribution/distribution` and `dozzle` are both plain HTTP services with no known Windows/Docker-Desktop-specific issues (verified: neither requires the Docker socket the way Traefik's label provider does — Portainer *does* need docker.sock, but only for read/display, which is a different, lower-risk usage pattern than Traefik's provider-driver use; to be empirically confirmed at implementation time, flagged here rather than assumed).

## Decision hierarchy applied

| Need (from the 10-experiment list) | Decision | Mechanism |
|---|---|---|
| ECR image lifecycle | **REUSE** | `distribution/distribution` registry container; `docker build`/`tag`/`push`/`pull` against it — real image storage, real manifest digests |
| ECS task = container | **REUSE** | Docker Compose itself — no wrapper needed, a container's lifecycle already *is* the real behavior being taught |
| desired_count / scaling | **REUSE** | `docker compose up -d --scale app=N` — native Compose feature, real |
| Task replacement on crash | **REUSE (Docker's own mechanism)** | `restart: on-failure` policy — real daemon-level restart, honestly labeled BEHAVIOR-EQUIVALENT (same container ID restarts; real ECS launches a new task ID — documented, not hidden) |
| Task role / metadata | **REUSE, proven in R1** | `amazon-ecs-local-container-endpoints` |
| Health check / ALB | **REUSE, proven in R2** | Traefik, file-provider mode, dynamically regenerated on scale |
| Container visualization | **REUSE** | Portainer |
| Logs | **REUSE** | Dozzle |
| OOM / resource limits | **REUSE (Docker's own mechanism)** | `mem_limit` in Compose — real Linux cgroup enforcement via Docker Desktop's WSL2 backend, real OOM-kill, no wrapper |
| Bad image / pull failure | **REUSE (Docker's own mechanism)** | Reference a nonexistent tag — real `docker pull` failure, zero code |
| App itself (self-identify, /health, VERSION, memory-eating endpoint) | **ADAPT** | Extend R2's `app/server.py` (~15-20 added lines: `/oom` endpoint, `VERSION` env var) — not a new build, an extension of an already-proven asset |
| Dynamic Traefik backend list on scale | **BUILD (thin, unavoidable)** | One script regenerating `traefik-dynamic.yml` from `docker compose ps` — justified because file-provider mode (itself a workaround for a real, documented Windows issue) has no auto-discovery |

## What was explicitly NOT built
No ECS scheduler clone. No custom registry. No custom log viewer. No custom container dashboard. No custom load balancer. The only "build" is ~20 lines of app extension plus one reconciliation script — both justified by name above, not by default.

## Confidence check on the zero-search-results claim
Ran the exact compound query specified ("ecs fargate local simulation") via the GitHub search API — zero items returned, not merely "nothing good found." This is the same negative-evidence pattern established in the Phase-Audit and R1/R2 audits: absence of results is recorded as a real finding, not assumed.

---

## Post-implementation addendum

**Portainer**: decided against, per the approval's "reuse only if useful" guidance — Traefik's dashboard (routing/health) + Dozzle (logs/container list) + `docker compose ps`/`inspect` (state/restart-count) together covered every state needed across all 10 experiments without a third overlapping dashboard.

**Dynamic Traefik reload script**: the architecture proposal planned one; **not built**. Discovered during implementation that listing all 3 backends statically in `traefik-dynamic.yml` and relying on Traefik's own real health check to mark stopped ones DOWN achieves the same "desired_count" visualization with less code and higher fidelity (it's Traefik's real health-check mechanism doing the work, not a custom script inferring state). One less component than approved, not more.

**`/crash` endpoint**: added mid-implementation, not in the original approved scope, after real investigation (see `R3-REPORT.md` §H) showed `docker kill` doesn't exercise Docker's restart policy. This is the one deviation from the approved custom-code list, justified inline in the report rather than silently added.
