# R13-04 — SPOILER — ROOT CAUSE

## What was injected
`inject.sh` ran real `stress-ng --vm 1 --vm-bytes 300M --vm-keep` inside one specific pod (via `kubectl exec`), whose deployment sets a real `limits.memory: 128Mi` — the same mechanism R10-05 already validated, reused unmodified here as the hidden fault.

## Real observed evidence
- `evidence/pod-watch.txt`: pod `r10-app-76f9494cd7-5tvkk` shows `RESTARTS: 1` while its sibling `...qsl9d` stays at `0` — **the same pod name recurs**, this is not random across the fleet.
- `evidence/pod-describe.txt` (`kubectl describe pod`): `Last State: Terminated`, `Reason: OOMKilled`, `Exit Code: 137`, `Restart Count: 1` — the real cgroup OOM killer, confirmed via the orchestrator's own record, not inferred.
- The command itself: `kubectl exec ... stress-ng` returned `command terminated with exit code 137` — the real Kubernetes-managed container was killed mid-command.

## Root cause
The pod's memory limit (128Mi) is smaller than the workload attempted to allocate (300M via stress-ng standing in for a real memory-hungry code path/leak). Kubernetes' kubelet enforces this via the same cgroup memory limit mechanism already proven at the plain-Docker level in R3/R5 — now enforced by the orchestrator, which also automatically restarts the killed container. The "random-looking" restarts are not random: `kubectl describe pod` on the specific recurring pod name proves it every time, ruling out flaky infrastructure or a scheduler issue.

## Immediate mitigation
Stop the memory-hungry process (it already finished, since `stress-ng --timeout 30s` was time-bounded) — in a real incident this is "identify and kill/redeploy the offending process/pod."

## Permanent fix / prevention
- Right-size `limits.memory` from real profiling of the workload's actual peak usage, not a guess.
- Add a memory-usage-trending alert (`container_memory_working_set_bytes` approaching `limits.memory`) as a leading indicator, so the pod is flagged before it gets OOMKilled, not only after.
- If the workload's memory need is genuinely variable/bursty, consider a higher limit with a lower `requests` value (Kubernetes' burstable QoS class) rather than a tight limit that guarantees repeated kills.

## AWS mapping
An EKS pod's `resources.limits.memory` set too low for its real workload — the exact same cgroup-based OOM enforcement mechanism as a bare EC2/ECS container, now visible at the Kubernetes orchestration layer (`kubectl describe pod` in place of `docker inspect`).
