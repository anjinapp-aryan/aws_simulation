# R10 Gap Analysis

## 1. R1-R9 coverage summary
| Phase | Concept | Hands-on |
|---|---|---|
| R1 | IAM/task credentials | Yes |
| R2 | ALB routing/health | Yes |
| R3 | ECS/ECR/Fargate task lifecycle (crash, OOM, restart) | Yes |
| R4 | RDS connectivity/pooling/latency | Yes |
| R5 | CPU/memory pressure, cascading failure, observability | Yes |
| R6 | ElastiCache/caching, cache-aside, Sentinel failover | Yes |
| R7 | SQS-equivalent messaging, DLQ, retry, ordering | Yes |
| R8 | Distributed tracing | Yes |
| R9 | Circuit breaking / service resilience | Yes |

## 2. Already mastered concepts
Container lifecycle at the single-task level (start/stop/crash/restart/OOM), load balancing and health checks, database connection-pool behavior, caching patterns and failover, async messaging reliability, distributed tracing, and both infra- and app-level circuit breaking. All built on Docker **Compose**, which has no scheduler, no reconciliation loop, no rolling deployments, no resource-based pod eviction, and no service discovery beyond static DNS names.

## 3. Remaining major AWS architecture gaps
| Concept | R1-R9 coverage | Hands-on? | Visualization? | Interview value | $0 feasible? |
|---|---|---|---|---|---|
| **Container orchestration (EKS/Kubernetes fundamentals: scheduling, rolling deploys, self-healing, resource limits, HPA, service discovery)** | **None** | **Would be new** | **Strong (kube-state-metrics/Grafana, k8s dashboard)** | **Very high** | **Yes (kind/k3d)** |
| Blue-green/canary deployment | None standalone | Possible via Traefik weights, but narrower | Moderate | High | Yes |
| Secrets management/rotation | None | Possible (Vault) | Moderate | Medium-high | Yes |
| API Gateway/rate limiting | Trivial (Traefik middleware) | Low novelty | Low novelty | Medium | Yes, but low learning delta |
| Autoscaling | None | Mostly NOT POSSIBLE LOCALLY for real AWS scaling policies; K8s HPA is the one genuinely reproducible piece | Moderate | High | Partial |
| Multi-region/DR | None | Mostly NOT POSSIBLE LOCALLY | Low | High but low hands-on ceiling | No |
| Event-driven serverless (Lambda-style) | None | Cold-start concepts hard to simulate honestly | Low | High | Partial, weak fidelity |

## 4. Candidate R10 topics (ranked)
1. **Container orchestration fundamentals (Kubernetes, standing in for EKS)** - biggest remaining gap, highest combined score.
2. Blue-green/canary deployment - solid but smaller; naturally becomes one of the orchestration lab's own experiments (K8s rolling updates) rather than a separate phase.
3. Secrets management (Vault) - good standalone future phase, doesn't depend on anything unfinished.
4. Autoscaling - genuinely valuable only via K8s HPA, which the orchestration phase can include as one experiment; true AWS ASG/ECS scaling-policy behavior is NOT POSSIBLE LOCALLY regardless.
5. API Gateway/rate limiting - deprioritized, too small a delta over existing Traefik knowledge.
6. Multi-region/DR - deprioritized, fidelity ceiling too low for a dedicated phase.

## 5. Recommended R10 topic
**Container orchestration fundamentals** - Kubernetes (real, local, via `kind`), standing in for the concepts EKS/ECS's own scheduler and control loop implement: pod scheduling, rolling deployments, self-healing/reconciliation, resource requests/limits and eviction, readiness/liveness probes, service discovery, and Horizontal Pod Autoscaling.

## 6. Why this topic wins
- It is the single largest capability gap: every prior phase ran on Compose, which has none of Kubernetes' (or ECS's) reconciliation-loop behavior - "if a pod/task dies, something actively notices and replaces it" has never actually been demonstrated, only Docker's much simpler `restart:` policy (R3).
- Extremely high Senior/Architect interview value - EKS, pod scheduling, resource limits/OOM at the orchestrator level, rolling updates, and HPA are constant interview topics that this project has not yet touched.
- Strong, mature GitHub reuse: `kind` (official Kubernetes SIG project) or `k3d` for the cluster itself, `kube-state-metrics` + the existing Grafana/Prometheus pattern for visualization, `metrics-server` for real HPA - no custom simulator needed anywhere.
- Naturally **subsumes** blue-green/canary (via rolling update strategy) and the genuinely-reproducible part of autoscaling (HPA) as experiments within it, rather than needing separate phases for each.
- $0 and fully local - `kind`/`k3d` create a real (if single-node) Kubernetes cluster inside Docker, no cloud account needed.

## 7. Why other candidates were not selected
- Blue-green/canary: real value, but standalone it's a much smaller lab than what K8s rolling updates already demonstrate as a side effect - folding it in is more efficient than a dedicated phase.
- Secrets management: legitimate future phase, but doesn't address as large a gap; queued as a good R11+ candidate.
- Autoscaling: mostly NOT POSSIBLE LOCALLY for real AWS control-plane scaling; only its K8s HPA analog is honestly reproducible, so it's folded into R10 rather than justifying its own phase.
- API Gateway/rate limiting: too small a delta over already-demonstrated Traefik knowledge to justify a full phase.
- Multi-region/DR: fidelity ceiling too low locally to be worth a dedicated phase right now.
