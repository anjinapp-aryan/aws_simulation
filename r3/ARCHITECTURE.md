# R3 Proposed Architecture (NOT YET IMPLEMENTED)

```
                    Browser / curl
                          |
                          v
                     Traefik (:28080 traffic, :28081 dashboard)
                     file-provider, dynamic file regenerated on scale
                          |
              +-----------+-----------+-----------+
              |           |           |    (up to N, scale test)
           Task-1      Task-2      Task-3
        (container)  (container)  (container)
              |           |           |
           App image pulled from local registry (:5000)

  Sidecars (all reused, unmodified):
    - distribution/distribution (:5000)  -- local "ECR" -- real push/pull
    - Portainer (:29000)                 -- task/container state dashboard
    - Dozzle (:29999)                    -- real-time log viewer
    - amazon-ecs-local-container-endpoints -- task-role credential vending (carried from R1)
```

## Component decisions (from REUSE-AUDIT.md)

| Layer | Tool | Status |
|---|---|---|
| Proxy / ALB-equivalent | Traefik v3.1, file provider | Reused, config pattern carried from R2 |
| ECR-equivalent | `registry:2` (distribution/distribution) | Reused, unmodified |
| Task/container | Docker Compose | Reused, native mechanism |
| Container dashboard | Portainer | Reused, unmodified |
| Log viewer | Dozzle | Reused, unmodified |
| Task-role/metadata | amazon-ecs-local-container-endpoints | Reused, carried from R1 |
| App | `labs/R2-alb-behavior/app/server.py` | **Adapted**: add `VERSION` env var (trivial, likely already trivially settable), add `/oom` endpoint (~10 lines) that allocates memory in a loop until killed |
| Scale-triggered Traefik reload | New script | **Built** — regenerates `traefik-dynamic.yml` from live `docker compose ps` output, since file-provider has no auto-discovery |

## Experiment-to-mechanism mapping (proposed, not yet run)

| # | Experiment | Real mechanism |
|---|---|---|
| 1 | Normal service, desired_count=2 | `docker compose up -d --scale app=2` |
| 2 | Task lifecycle + reconciliation | `restart: on-failure` (Docker's real restart policy) + reload script |
| 3 | Health failure, container alive | Reuse R2's `/tmp/unhealthy` toggle pattern exactly |
| 4 | Application crash | `docker kill` a container; `restart: on-failure` brings it back — same mechanism as #2, different trigger |
| 5 | Bad image | Reference nonexistent tag; real `docker pull` failure |
| 6 | Image versioning | `docker build -t localhost:5000/app:v1` vs `:v2`, push to the real local registry, observe response change |
| 7 | OOM | `mem_limit: 20m` + new `/oom` endpoint | 
| 8 | Logs | Dozzle, zero extra config |
| 9 | Scaling 1→2→3 | `docker compose up -d --scale app=N` + reload script |
| 10 | Failure + recovery under load | Combination of #2/#4 with continuous `test.sh`-style traffic (reused from R2) |

## Known fidelity limitations, stated up front (not discovered later)

- "Task replacement" is really the **same container restarting** (Docker restart policy), not a **new task with a new ID** (real ECS behavior) — will be labeled BEHAVIOR-EQUIVALENT, not REAL, in every experiment where it appears.
- Traefik's scale-awareness is **manual-trigger, script-driven**, not automatic service discovery — a direct consequence of the R2-established file-provider workaround, not a new limitation.
- No real Fargate compute isolation (no microVM boundary) — Docker containers share the host kernel, unlike Fargate's per-task isolation. Labeled "partial fidelity" per the required Real-vs-Simulated table.
- OOM behavior depends on Docker Desktop's WSL2 backend correctly enforcing `mem_limit` via cgroups — asserted as generally reliable, but will be **empirically verified**, not assumed, when Experiment 7 actually runs.

## What requires this turn's review before proceeding
Per the stop condition: this architecture and the reuse audit are presented for review. No `docker compose up`, no image builds, no script execution has occurred this turn.
