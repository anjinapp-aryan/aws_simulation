# R10 Reuse Audit — Container Orchestration (Kubernetes, standing in for EKS)

## 1. Searches performed (real, GitHub Search API)
| Query | Result |
|---|---|
| `kubernetes local chaos lab docker` | 0 results |
| `kind cluster chaos engineering demo` | 0 results |

No integrated tool exists - consistent with every prior audit in this project. Compose mature standalone projects.

## 2. Candidate repositories

| Component | Repository | Stars | Actual License | Activity | Decision | Reason |
|---|---|---|---|---|---|---|
| Local cluster | `kubernetes-sigs/kind` | 15,484 | Apache-2.0 (verified) | pushed 2026-09-04, active | **REUSE** | Official Kubernetes SIG project, kubeadm-based (closest to "vanilla" control-plane behavior of any local option), the standard tool for CI-grade local Kubernetes testing |
| Local cluster (alternative) | `k3d-io/k3d` | 6,551 | MIT (verified) | pushed 2026-09-07, active | **REFERENCE** | Real, CNCF-conformant (k3s), lighter/faster than kind, but kubeadm-based `kind` was chosen as primary for closer fidelity to EKS's control-plane shape; noted as a lighter alternative if resource-constrained |
| Local cluster (alternative) | `kubernetes/minikube` | 32,120 | Apache-2.0 (verified) | pushed 2026-09-11, active | **REFERENCE** | Most popular by stars, but adds a VM/driver abstraction layer `kind` doesn't need on Docker Desktop - `kind` is the more direct fit for this project's existing Docker-only environment |
| Metrics | `kubernetes/kube-state-metrics` | 6,197 | Apache-2.0 (verified) | pushed 2026-09-08, active | **REUSE** | Official Kubernetes project, exposes real cluster/pod/deployment state as Prometheus metrics - feeds the existing Grafana/Prometheus pattern from R4-R9 unchanged |
| Autoscaling | `kubernetes-sigs/metrics-server` | (official K8s SIGS project) | Apache-2.0 | active | **REUSE** | Required for real HPA (Horizontal Pod Autoscaler) to function - without it, HPA cannot read pod CPU/memory at all |
| Visualization (dashboard) | `kubernetes/dashboard` | 15,414 | Apache-2.0 (verified) | pushed 2026-01-21 (~8mo old) | **REFERENCE** | Real, official, but Grafana+kube-state-metrics (already proven, already in the stack) is preferred as primary visualization for consistency with R4-R9; the K8s Dashboard is available as a secondary/optional view, not required |
| Chaos injection | `kubectl delete pod` / `kubectl drain` (built into Kubernetes itself) | — | Apache-2.0 (Kubernetes core) | — | **REUSE** | Kubernetes' own real reconciliation behavior is the thing being tested - no external chaos tool needed for pod-kill/node-drain experiments, same "use the real mechanism" principle as R3's `docker kill` |
| Chaos injection (advanced, optional) | `chaos-mesh/chaos-mesh` | 7,890 | Apache-2.0 (verified) | pushed 2026-09-10, active | **REFERENCE** | Real, mature, CNCF project for K8s-native network/IO chaos - noted as a stretch/future addition if simple `kubectl`-based chaos proves insufficient, not required for R10's core scope |

## 3. Visualization strategy
Primary: Grafana + Prometheus (reused unchanged from R4-R9) fed by `kube-state-metrics` (real pod/deployment/replica state) and `metrics-server` (real CPU/memory for HPA). Secondary/optional: `kubectl get pods -w` (real live CLI watch, zero extra infra) and the official Kubernetes Dashboard if useful. No custom UI.

## 4. Existing R1-R9 components reused
Grafana, Prometheus (exact provisioning pattern from R4-R9). The application itself can be the same minimal Python server pattern used throughout R2-R9, containerized identically - just scheduled by Kubernetes instead of Compose.

## 5. What must be built
Kubernetes manifests (Deployment, Service, HPA, resource requests/limits, readiness/liveness probes) - these are configuration, not code, analogous to how `docker-compose.yml` itself isn't "custom code." If any experiment genuinely needs an app change (e.g., an endpoint to generate CPU load for HPA testing), it will reuse the existing R5 `stress-ng`-based pattern rather than writing new load-generation code.

## 6. $0 proof
`kind`/`k3d` create a real Kubernetes cluster entirely inside Docker containers on the local machine - no cloud account, no AWS credential, no EKS control-plane charge. All other components already verified free in R4-R9.
