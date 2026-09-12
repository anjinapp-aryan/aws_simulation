# R3 Experiments — Action / Observed / Evidence / Fidelity

| # | Action | Observed | Visualization used | Fidelity |
|---|---|---|---|---|
| R3-01 | Start desired_count=2, build+push v1 | Both UP, alternating traffic, registry has v1 | Traefik API + curl | High behavioral |
| R3-02 | `stop`/`start` app-1 | Up→Exited(137)→Up, same container ID, no auto-recovery | `docker compose ps` timestamps | Behavior-equivalent |
| R3-03 | Break `/health` only | Container Up throughout, Traefik DOWN→UP | Traefik `serverStatus` | High |
| R3-04 | `/crash` self-exit | `RestartCount` 0→1, automatic, ~2s | `docker inspect` | Behavior-equivalent (real Docker restart, not real ECS task replace) |
| R3-05 | Run nonexistent tag | Real registry 404 error text | terminal | High — genuinely the same failure class as ECR pull failure |
| R3-06 | Build+push v2 | v1 tasks say VERSION=1, fresh v2 says VERSION=2 | curl + registry catalog | High — real image lifecycle |
| R3-07 | `/oom` at `mem_limit=128m` | `OOMKilled=true` caught live, `RestartCount` climbs | polled `docker inspect` | High — real cgroup OOM |
| R3-09 | Scale 1→2→3→2 | UP count tracked each step, one timing artifact noted | Traefik `serverStatus` | High, timing caveat documented |
| R3-10 | Kill app-1 under load | 9/10 requests OK, 1× HTTP 000 during detection gap | curl loop + Traefik API | High — realistic small failover gap, not hidden |

Full narrative, root-cause investigations, and fixes: `R3-REPORT.md` §G-K.
