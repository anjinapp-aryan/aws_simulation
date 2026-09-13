# R10 — Proposed Architecture (pending approval, nothing built yet)

## Diagram
```
Client (curl/vegeta)
  |
  v
Kubernetes Service (ClusterIP/NodePort - real kube-proxy load balancing)
  |
  v
Deployment (N real Pods, existing R2-R9 minimal-app pattern, unmodified image)
  |
  +-- readiness/liveness probes (real kubelet-enforced)
  +-- resource requests/limits (real cgroup enforcement, same mechanism R3/R5 already proved works - now orchestrator-managed)
  +-- HorizontalPodAutoscaler (real, driven by metrics-server)

Cluster: kind (real local Kubernetes, kubeadm-based, single control-plane + worker node(s), inside Docker)

Observability (REUSED pattern from R4-R9):
  kube-state-metrics + metrics-server -> Prometheus -> Grafana
  kubectl get pods -w / kubectl logs (real, zero extra infra)
```

## Components
| Component | Status |
|---|---|
| `kind` cluster | **NEW** |
| `kube-state-metrics`, `metrics-server` | **NEW** (official K8s projects, config only) |
| Kubernetes manifests (Deployment/Service/HPA/probes) | **NEW** (configuration, not code) |
| Prometheus, Grafana | **REUSED unchanged**, config from R4-R9 |
| app image | **REUSED unchanged** - same minimal server pattern, just scheduled differently |

## Data/request flow
Client -> K8s Service (real kube-proxy iptables/IPVS load balancing across live pod IPs) -> Pod -> app.

## Failure injection points
`kubectl delete pod` (real pod kill), `kubectl cordon`/`drain` (real node eviction), `stress-ng` inside a pod exceeding its memory limit (real OOM, reused from R5), a deliberately-failing readiness probe endpoint (new, ~10 lines).

## Visualization points
Grafana (pod count, restart count, resource usage - fed by kube-state-metrics/metrics-server, same dashboard pattern as R4-R9), `kubectl get pods -w` (real-time pod state transitions), `kubectl describe pod` (real event history - scheduling, probe failures, OOM kills).

## Experiments (8)

| ID | Purpose | What we break | How | Visualization | AWS mapping | Fidelity |
|---|---|---|---|---|---|---|
| R10-01 | Baseline: real scheduling | — | Deploy, observe pod placement | `kubectl get pods -o wide`, Grafana | ECS/EKS task placement | REAL |
| R10-02 | Self-healing / reconciliation loop | Kill a pod directly | `kubectl delete pod` | Watch a **new** pod get created automatically (contrast with R3's same-container restart) | EKS/ECS replacing a failed task | REAL |
| R10-03 | Rolling deployment (folds in blue-green/canary) | Deploy a new version | `kubectl set image` / apply updated Deployment | Continuous Vegeta traffic during rollout - measure real zero-downtime (or not) | ECS/EKS rolling deployment strategy | REAL |
| R10-04 | Resource limits & OOM at orchestrator level | Exceed pod memory limit | `stress-ng` inside the pod (reused R5 mechanism) | `kubectl describe pod` real `OOMKilled` event + automatic replacement | ECS task/EKS pod memory-limit enforcement | REAL |
| R10-05 | Readiness vs liveness | Fail readiness probe only | New `/ready` endpoint toggled unhealthy | Service endpoint list changes (pod stays running, traffic stops) | ALB/NLB target deregistration vs ECS task health | REAL |
| R10-06 | Node-level failure | Cordon + drain the node | `kubectl cordon` / `kubectl drain` | Pods evicted and rescheduled (single-node `kind` limits: reschedule may pend - documented honestly, not hidden) | EC2/managed-node-group failure in EKS | REAL, with an honestly-declared single-node ceiling |
| R10-07 | Horizontal Pod Autoscaler | Generate real CPU load | `stress-ng`/Vegeta against the app | Real automatic scale-out (measured pod count over time), then scale-in after load stops | ECS Service Auto Scaling / EKS HPA | REAL |
| R10-08 | Service discovery under scale | Scale replicas up/down | `kubectl scale` | Verify traffic actually distributes across all live pod IPs (real kube-proxy), contrast with Traefik's static list used in R2-R9 | ECS Service Discovery / EKS Service | REAL |

## REAL vs BEHAVIOR-EQUIVALENT vs NOT POSSIBLE LOCALLY
- **REAL**: `kind`'s actual Kubernetes control plane and reconciliation loop, real scheduling, real probes, real OOM enforcement, real HPA, real kube-proxy load balancing.
- **BEHAVIOR-EQUIVALENT**: this cluster standing in for EKS - same real Kubernetes engine, but no AWS-managed control plane, no VPC CNI, no IAM Roles for Service Accounts.
- **NOT POSSIBLE LOCALLY**: EKS's own managed control plane/API server SLAs, AWS VPC CNI networking, IRSA, EKS Fargate profiles, real multi-AZ node groups, Cluster Autoscaler provisioning real EC2 capacity.

## $0 proof strategy
`kind` runs entirely as Docker containers on the local machine - no cloud account, no AWS credential, no EKS control-plane charge (EKS itself costs money per cluster-hour on real AWS; this is explicitly why `kind` is used instead). All other components already verified free in R4-R9.

## Cleanup strategy
`kind delete cluster` (removes the entire cluster and all its Docker-backed nodes in one command) + `docker compose down -v` for the Grafana/Prometheus stack if run separately. Verify via `docker ps -a`, `docker network ls`, `kind get clusters` (should return empty).

---

## R10 RECOMMENDATION

**Topic**: Container orchestration fundamentals (Kubernetes via `kind`, standing in for EKS)
**Why**: Largest remaining capability gap - no prior phase demonstrated a real reconciliation loop, real scheduling, or real self-healing beyond Docker's simple restart policy.
**Senior/Architect value**: Very high - EKS/pod scheduling/resource limits/rolling deployments/HPA are core, constantly-asked interview topics untouched until now.
**Hands-on value**: Very high - 8 genuinely new failure/recovery experiments, none repeating prior phases' mechanisms except where reused deliberately (stress-ng, Vegeta, Grafana/Prometheus).
**Visualization**: Grafana/Prometheus (reused pattern) + real `kubectl` live state - no custom UI.
**GitHub reuse**: `kind`, `kube-state-metrics`, `metrics-server` all official/mature Apache-2.0 projects; `kubectl delete/drain` reuses Kubernetes' own real mechanisms as the fault-injection tool, per this project's standing principle of using the real mechanism over a custom chaos tool.
**Custom build**: Kubernetes manifests (config, not code) + one small `/ready` toggle endpoint (~10 lines) on the existing app.
**$0 feasibility**: Yes - fully local, no AWS account needed.
**REAL**: Scheduling, reconciliation, probes, OOM enforcement, HPA, kube-proxy load balancing.
**BEHAVIOR-EQUIVALENT**: EKS control-plane behavior generally (same real K8s engine, no AWS management layer).
**NOT POSSIBLE LOCALLY**: EKS's managed control plane, VPC CNI, IRSA, Fargate profiles, real multi-AZ node groups, Cluster Autoscaler's real EC2 provisioning.
**Estimated experiments**: 8.

---

STOPPING HERE per instructions. Waiting for **"R10 ARCHITECTURE APPROVED"** before writing any manifests, scripts, or code.
