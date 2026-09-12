# R5 GitHub Reuse Audit — Production Observability + Troubleshooting

## Search queries run this turn (real, not assumed)
`aws production troubleshooting lab prometheus jaeger docker` → **0 results**. Same negative-evidence pattern as every prior audit (Phase-Audit, R1-R4) — no integrated lab exists; components compose.

## Candidates evaluated

| Repo | Stars | License | Last push | Capability | Verdict |
|---|---|---|---|---|---|
| ColinIanKing/stress-ng | 2,763 | GPL-2.0 | 2026-09-03 | Real CPU/memory/IO stress generator, the canonical Linux tool for this | **REUSE** — via `docker exec`, same direct-invocation pattern as R4's `pgbench` |
| alexei-led/pumba | 3,147 | Apache-2.0 | 2026-09-10 | Docker-native chaos (kill/pause/network emulation), bundles stress-ng internally | **REFERENCE** — capable, but adopting a whole new orchestration tool duplicates what direct `docker kill`/`stress-ng exec` already proved reliable in R1-R4; would add a dependency without adding capability |
| jaegertracing/jaeger | 23,201 | Apache-2.0 | 2026-09-10 | Real distributed tracing, waterfall UI | **REFERENCE this phase, not core** — see cost/benefit note below |
| tsenart/vegeta | 25,186 | MIT | 2026-02-16 | Real sustained HTTP load generator with rate control | **REUSE** for generating realistic traffic during CPU/latency experiments, better than ad-hoc curl loops |
| google/cadvisor | 19,417 | Apache-2.0 (verified directly, GitHub API misreported NOASSERTION) | 2026-09-09 | Real per-container CPU/memory/network metrics, Prometheus-scrapable | **REUSE** — the real "CloudWatch container metrics" equivalent, closes the one metrics gap R1-R4 didn't need |
| Grafana / Prometheus / Dozzle / Traefik / Toxiproxy / Postgres / PgBouncer / pgweb | — | — | — | Already reused and proven working (R2-R4) | **REUSE, carried forward unchanged** |

## Jaeger cost/benefit (the one real judgment call this audit makes)
Jaeger itself is a strong, mature, free candidate. The blocker isn't Jaeger — it's that **making it useful requires instrumenting the app with the OpenTelemetry Python SDK** (spans, context propagation, an OTLP exporter), which is a meaningfully larger amount of new code than the ~30-55 line pattern used for every app addition so far (R2's health toggle, R3's `/oom`/`/crash`, R4's `/db`). That violates "minimize custom code" unless the learning value clearly justifies it.

**Decision: Jaeger is REFERENCE for R5 (documented, not deployed) — proposed as R5's explicit stretch goal, not core scope.** Core R5 achieves "log/metric correlation" and "request tracing across components" via Dozzle (logs) + Prometheus/Grafana (metrics) + cAdvisor (container-level metrics), which are all zero-new-code reuses. If you want real distributed tracing, say so explicitly and I'll scope the OpenTelemetry instrumentation as its own reviewed addition rather than slipping it in.

## Decision hierarchy applied

| Need | Decision | Mechanism |
|---|---|---|
| CPU pressure | REUSE | `stress-ng --cpu N` via `docker exec` into the app container |
| Memory pressure | REUSE | `stress-ng --vm 1 --vm-bytes <N>` via `docker exec`, against the same real `mem_limit` cgroup enforcement R3 already proved works |
| Container-level CPU/mem metrics | REUSE | cAdvisor → Prometheus (new panel data, same Grafana instance from R4) |
| HTTP load generation | REUSE | vegeta, replacing ad-hoc curl loops for anything needing sustained/rate-controlled traffic |
| Dependency failure (DB) | REUSE, carried forward | Toxiproxy, exact mechanism proven in R4 |
| 5xx / unhealthy backend | REUSE, carried forward | Traefik health checks + real app failure modes, exact mechanism proven in R2/R3 |
| Logs | REUSE, carried forward | Dozzle |
| Metrics/dashboards | REUSE, carried forward | Prometheus + Grafana |
| Distributed tracing | REFERENCE (stretch, not core) | Jaeger — deferred pending your explicit approval given the real added-code cost |
| Cascading-failure demonstration (R5-06) | **Compose existing reused pieces only** | Chain: Toxiproxy DB latency → app response slows → Traefik health check starts flapping → visible on Grafana. No new tool — this is exactly what "compose existing projects" means, not a new experiment mechanism |

## Estimated custom code
Near-zero for the core scope: the app from R4 (`labs/r4-rds/app/server.py`) already has `/db`; R5 needs it reachable behind Traefik (a compose wiring change, not new code) plus `stress-ng` added to its Dockerfile (`apt-get install stress-ng`, one line). No new Python code required unless Jaeger is approved.

## Real-vs-simulated boundary (proposed)
| AWS capability | Local simulation | Fidelity |
|---|---|---|
| ECS task CPU pressure | Real `stress-ng --cpu` inside the real container, real cgroup CPU throttling | High behavioral |
| ECS task OOM | Real `stress-ng --vm` against real `mem_limit`, same mechanism R3 proved | High behavioral |
| ALB 5xx / unhealthy target | Real Traefik health-check state change, exact R2/R3 mechanism | High behavioral |
| RDS dependency failure | Real Toxiproxy fault, exact R4 mechanism | High behavioral |
| CloudWatch container metrics | cAdvisor → Prometheus → Grafana | Behavioral, real metrics |
| X-Ray / distributed tracing | Jaeger, if approved | Would be behavioral, real traces — not deployed yet |
| ECS task replacement (exact semantics) | Docker restart (same container ID) | **Not identical** — documented every time, per R3's established language |
| AWS's actual autoscaling response to CPU pressure | **NOT REPRODUCIBLE LOCALLY** | Deferred to real-AWS lab |

## $0 cost analysis
All candidates are free, self-hosted, open-source. No AWS account, credential, or paid tier anywhere. Consistent with R1-R4.

## Post-implementation revalidation (real, not assumed)
- **vegeta**: no official `tsenart/vegeta` Docker image exists. Used the actively-maintained community image `peterevans/vegeta` (same reasoning as `edoburu/pgbouncer` in R4 - real upstream binary, third-party packaging). Actually run: 150+100 real HTTP requests through Traefik, real latency/success numbers captured.
- **stress-ng**: `colinianking/stress-ng` (official author's own Docker Hub account, 5,700+ tags, actively pushed) confirmed real. Staged into the running `app` container via `docker cp` (binary path `/usr/bin/stress-ng`, not `/stress-ng` as first assumed - see R5-REPORT.md bug log) + `docker exec`, per the "don't modify the app image" rule. Actually ran real CPU (200% across 2 workers) and memory (real OOM) pressure.
- **cadvisor**: deployed successfully (`gcr.io/cadvisor/cadvisor:v0.49.1`, then `v0.52.1`) but its Docker container enumeration does not work on this Docker Desktop (API 1.54) - confirmed on two image versions and with an explicit `DOCKER_API_VERSION` pin, while Dozzle on the identical docker.sock mount works fine. This is a real, investigated, documented limitation (see R5-REPORT.md §10), not a config mistake. `docker stats`/`docker inspect` used instead for per-container CPU/memory evidence, consistent with the mechanism already proven in R1-R4.
- **pumba, Jaeger**: not deployed, per the original decision - reconfirmed still correct after execution (no experiment needed either).
