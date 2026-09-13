# R10 — Kubernetes/EKS Fundamentals Report

## 1. Objective
Experience real container orchestration mechanisms - scheduling, self-healing, rolling deployment, readiness/liveness, resource-limit enforcement, node failure, HPA, and service discovery - none of which Docker Compose (used in every prior phase) actually implements.

## 2. GitHub reuse decisions
Full detail: `R10/REUSE-AUDIT.md`. `kubernetes-sigs/kind` (15,484★, Apache-2.0, verified) - real, official, kubeadm-based local cluster. `kubernetes/kube-state-metrics` and `kubernetes-sigs/metrics-server` (both official Apache-2.0 projects) - reused unmodified. `kubectl delete/cordon/drain` reused as the fault-injection mechanism itself - no external chaos tool needed, same "use the real thing" principle as R3/R9. Grafana/Prometheus reused unchanged in pattern from R4-R9, redeployed as Kubernetes manifests instead of Compose services.

## 3. Final architecture
```
kind cluster (1 control-plane + 2 workers, real, inside Docker)
  Client -> Service (NodePort, real kube-proxy) -> Pods (Deployment, 2-6 replicas via HPA)
  kube-state-metrics + metrics-server -> Prometheus -> Grafana
```

## 4. Components actually used
New: `kind` v0.24.0, `kindest/node:v1.31.0`, official `metrics-server` (kind-patched with `--kubelet-insecure-tls`, a real documented compatibility requirement), official `kube-state-metrics`. Reused unchanged (config only): `prom/prometheus`, `grafana/grafana`.

## 5. Custom code
`app/server.py` (~50 lines): same minimal pattern as every prior phase, with independently-toggleable `/health` (liveness) and `/ready` (readiness) flags. Kubernetes manifests (Deployment/Service/HPA) are configuration, not code.

## 6-9. Experiments — all 8 executed for real, actual results

### R10-01 Scheduling
3 replicas scheduled real-for-real across the 2 worker nodes (control-plane excluded by its default taint - real scheduler behavior). Real Service endpoints list showed exactly 3 live pod IPs.

### R10-02 Pod self-healing (contrasted with R3)
Deleted pod `g9g8q`. Kubernetes created a **new pod with a different name** (`g4d4q`) - real `Scheduled -> Pulled -> Created -> Started` event sequence. This is the exact, proven contrast with R3: Docker's `restart:` policy reuses the same container; Kubernetes' ReplicaSet controller replaces the Pod entirely.

### R10-03 Rolling deployment
Continuous traffic (0.25s interval) during a real `v1 -> v2` rollout: **47/47 requests HTTP 200**, live transition from 9 v1 responses to 38 v2 responses, zero errors. Real `maxSurge:1, maxUnavailable:0` strategy proven zero-downtime under actual load, not asserted.

### R10-04 Readiness vs liveness (proven, not assumed)
Readiness failure: pod stayed `Running` (0/1 Ready), `RestartCount` stayed 0, and the pod's IP was removed from the Service's real endpoint list - traffic stopped, container kept running.
Liveness failure: kubelet actually killed and recreated the container - real event `Killing...will be restarted`, `RestartCount` incremented `0 -> 1`, confirmed via the real `.status.containerStatuses[0].restartCount` field.
This is the exact experimentally-proven distinction the architecture called for.

### R10-05 Resource pressure / OOM
Real `stress-ng --vm-bytes 300M` inside a pod with a 128Mi memory limit. Exit code **137** (SIGKILL). `kubectl describe pod` confirmed `Last State: Terminated, Reason: OOMKilled, Exit Code: 137`, `Restart Count: 2`. Pod recovered automatically, orchestrator-level OOM enforcement fully proven (same cgroup mechanism as R3/R5, now orchestrator-managed).

### R10-06 Node cordon + drain
Cordoned `r10-worker2` - real `Ready,SchedulingDisabled` status. Drained it - real eviction of the app pod, **automatically rescheduled to `r10-worker`** as a brand-new pod (`wxgvf`). Uncordoned to restore full cluster capacity.

### R10-07 HPA scale-out/scale-in (measured, not assumed)
Real `stress-ng --cpu 1 --cpu-load 100` in both pods. Measured, timestamped sequence: CPU 5% -> 176% -> 501%, real deployment event **"Scaled up replica set r10-app-66fd5b64bf to 6 from 2"**. After load stopped, real measured scale-in: CPU dropped to 18% at 20:23:04, replicas **6 -> 3 -> 2** by 20:23:55, matching the configured `stabilizationWindowSeconds: 30`. A complete, real, precisely-timed autoscaling cycle.

### R10-08 Service discovery (contrasted with R2/R3)
Scaled 2 -> 4 -> 1 -> 2 replicas under continuous traffic. **4 distinct real pods** actually served requests as the endpoint set changed live, confirmed via real kube-proxy load balancing. **Real bug/finding**: scaling to 1 replica was immediately overridden back to 2 by the HPA controller (`minReplicas: 2`) on its next reconcile cycle - a genuine, valuable lesson that HPA and manual `kubectl scale` are not independent; HPA wins. Contrasted explicitly with R2/R3's static Traefik file-provider backend list, which has no reconciliation loop at all.

## 10-11. Real bugs found and root-caused

**Bug 1 - `kind.exe` couldn't find `docker` from Git Bash.** SYMPTOM: `exec: "docker": executable file not found in %PATH%` even though `docker` worked fine directly in the same bash session. ROOT CAUSE: prepending a raw POSIX-style path to `$PATH` in Git Bash broke MSYS's PATH-to-Windows translation for the native `kind.exe` subprocess, so its own child-process (`docker`) lookup received a malformed PATH. FIX: ran all `kind`/`kubectl` commands via PowerShell instead, which handles native Windows PATH correctly - a genuine, documented environment quirk, consistent with this project's Windows/Git-Bash-specific findings in R2-R9.

**Bug 2 - HPA silently overrides manual scaling.** Not a defect - a real, valuable discovery documented in R10-08 above.

**Bug 3 (non-issue, investigated) - `RESTARTS: 0` appeared to not increment immediately after the liveness-triggered kill event.** Investigated by re-querying `.status.containerStatuses[0].restartCount` a few seconds later once the new container had actually started - confirmed it was a real timing/propagation delay in `kubectl get pod`'s cached view, not a missed restart. `RestartCount` correctly showed `1`, then `2` after the later OOM kill.

**Bug 4 (real, minor) - `kind delete cluster` left the shared `kind` Docker network behind** even with zero clusters remaining. Investigated (`docker network inspect kind` confirmed 0 attached containers) and removed explicitly (`docker network rm kind`) as part of full cleanup.

## 12. REAL vs BEHAVIOR-EQUIVALENT vs NOT POSSIBLE
**REAL**: `kind`'s actual Kubernetes control plane and scheduler, real ReplicaSet reconciliation, real readiness/liveness probe enforcement, real cgroup-based OOM enforcement, real HPA driven by real metrics-server data, real kube-proxy service-endpoint load balancing, real node cordon/drain eviction.
**BEHAVIOR-EQUIVALENT**: this cluster standing in for EKS - same real upstream Kubernetes engine (`kindest/node:v1.31.0`), but no AWS-managed control plane.
**NOT POSSIBLE LOCALLY**: EKS's own managed control plane/API server SLA, AWS VPC CNI networking, IAM Roles for Service Accounts (IRSA), EKS Fargate profiles, real multi-AZ managed node groups, Cluster Autoscaler provisioning real EC2 capacity.

## 13. AWS/EKS mapping (concise, per experiment)
- R10-01/02: EKS/ECS task placement and replacement - same reconciliation-loop concept.
- R10-03: ECS/EKS rolling deployment strategy (`maxSurge`/`maxUnavailable` map directly to ECS's `minimumHealthyPercent`/`maximumPercent`).
- R10-04: ALB/NLB target deregistration (readiness) vs. ECS task health-check-driven replacement (liveness) - two genuinely different AWS mechanisms this experiment cleanly separates.
- R10-05: ECS task / EKS pod memory-limit enforcement - same cgroup mechanism at a different orchestration layer than R3/R5.
- R10-06: EC2/managed-node-group failure or planned maintenance in EKS.
- R10-07: EKS HPA / ECS Service Auto Scaling - the one genuinely reproducible piece of "autoscaling" identified in the R10 gap analysis.
- R10-08: EKS Service / ECS Service Discovery - real dynamic endpoint management vs. R2/R3's static backend list.

## 14. Senior/Architect interview takeaways (derived only from what was actually run)
- "What's the difference between a container restart and a pod replacement?" - I can answer from direct comparison: R3's Docker restart reuses the same container; R10-02 showed Kubernetes creating an entirely new Pod object with a new name and full scheduling cycle.
- "Explain readiness vs liveness probes." - I have exact evidence: readiness failure removed a still-running pod from Service endpoints without any restart; liveness failure triggered a real kubelet-driven container kill and restart, with the restart count as proof.
- "How does HPA actually behave under load, and what determines its timing?" - I measured a real scale-out (2->6 replicas as CPU hit 501%) and scale-in (6->2, gated by `stabilizationWindowSeconds: 30`), and can explain the HPA-vs-manual-scaling conflict from R10-08's real finding.
- "What happens to workloads during a node failure or maintenance?" - I drained a real node and watched Kubernetes reschedule the evicted pod onto a healthy node automatically, the same mechanism behind EKS managed-node-group replacement or AZ failure recovery.

## 15. $0 proof
`kind` created a real Kubernetes cluster entirely as Docker containers on the local machine. No AWS credential was referenced anywhere in any manifest or script. No AWS API call was made.

## 16. Cleanup proof
`kind delete cluster --name r10` - verified via `kind get clusters` returning empty. `docker ps -a | grep r10` - empty. The leftover shared `kind` Docker network was investigated (confirmed 0 attached containers) and explicitly removed. App images `r10-app:v1`/`:v2` removed from the local Docker image cache.

## 17. Limitations
Single-run experiments on a single-machine, 3-node cluster; no multi-AZ semantics; metrics-server required a kind-specific TLS flag not needed on EKS. HPA CPU-percentage readings were noisy/bursty at small pod counts (expected for a lab-scale workload, not investigated further as it didn't block the experiment's real objective).

## R10 STATUS: **PASS**
All 8 experiments actually executed against a real 3-node Kubernetes cluster, with real evidence (kubectl events, restart counts, HTTP status distributions, timestamped HPA replica counts) captured for each; 4 real findings investigated and root-caused, none hidden; visualization stack (Grafana/Prometheus/kube-state-metrics/metrics-server) deployed and functioning; complete, verified teardown; $0 cost.
