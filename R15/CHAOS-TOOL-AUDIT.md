# R15 — Chaos/Fault-Injection Tool Audit

Standing rule: search GitHub first, verify actual LICENSE (not badge), select the minimum viable toolset.

## Candidates evaluated

| Tool | Stars | License (verified) | Activity | Docker | K8s | Fault types | Verdict |
|---|---|---|---|---|---|---|---|
| `alexei-led/pumba` | 3148 | Apache-2.0 (verified: fetched actual `LICENSE`, genuine Apache header) | Active (pushed 2026-09-10) | Native, no daemon needed — drives the Docker API directly | No | container kill/pause/stop, network delay/loss/corruption/partition (via `tc`), CPU/memory stress via a helper container | Real, mature, genuinely usable |
| `chaos-mesh/chaos-mesh` | 7892 | Apache-2.0 (verified) | Active (pushed 2026-09-10) | No (K8s-only) | Yes — CRD-based, needs its own controller + admission webhook + dashboard deployed into the cluster | Pod kill, network chaos, I/O chaos, stress chaos, time chaos, DNS chaos, HTTP chaos | Real, mature, but a real *platform*, not a lightweight CLI |
| `litmuschaos/litmus` | 5610 | Apache-2.0 (verified) | Active (pushed 2026-08-25) | Partial | Yes — CRD-based, its own operator + ChaosHub | Similarly broad K8s fault catalogue | Real, mature, same platform-weight concern as Chaos Mesh |
| `powerfulseal/powerfulseal` | 1983 | Apache-2.0 | **Stale — last push 2023-11-10, ~3 years with no activity** | Yes | Yes | Pod/node kill, scheduled chaos | **Rejected on maintenance grounds** — exactly the kind of check this project's "stars alone are not sufficient" rule exists to catch |

## What R15 actually needs
Every fault type R15's incident scenarios require (process/container kill, network latency/loss/partition, CPU/memory pressure, dependency timeout, DB/replica failure, cache failure, queue-consumer failure, broker/connector pause, network-policy denial) is **already provided, already proven working in this exact repo, across R4-R14**, by mechanisms with zero new dependencies:

| Fault type | Already-proven mechanism | Proven in |
|---|---|---|
| Network latency/loss | Toxiproxy | R4, R6, R7, R8, R9, R11, R13 |
| Container kill/crash | `docker kill` | R3, R6, R9, R13, R14 |
| Container freeze / (with the real caveat about kernel-buffer behavior, discovered and documented) | `docker pause` | R14 |
| True network partition | `docker network disconnect`/`connect` | R14 |
| CPU/memory pressure | `stress-ng` inside a real pod | R10, R13 |
| DB/replica failure | Patroni's own real failover (R14), Toxiproxy on a DB path (R4/R13) | R4, R13, R14 |
| Cache failure | Valkey `CONFIG SET maxmemory` (R6/R13), Sentinel failover (R6) | R6, R13 |
| Queue/consumer failure | RabbitMQ TTL/DLQ mechanics, consumer crash (R7/R13) | R7, R13 |
| Broker/connector pause | Kafka Connect REST pause/resume (R11/R13) | R11, R13 |
| Network-policy denial | Real Cilium NetworkPolicy/CiliumNetworkPolicy (R12/R13) | R12, R13 |
| Backup/DR failure | pgBackRest/Velero real failure modes discovered in R14 (e.g., the hostPath/FSB incompatibility) | R14 |

## Decision: REUSE the already-proven native primitives; chaos frameworks are REFERENCE only
**Pumba** is a genuinely good, mature, correctly-licensed fit for Docker-based fault injection and was seriously considered as a drop-in replacement for this project's own `docker kill`/`pause`/`network disconnect`/Toxiproxy calls. It is not adopted because it would add a new dependency to reproduce exactly what already-proven, zero-dependency primitives do today — against the standing "minimum viable toolset" and "don't rebuild what R1-R14 already proved" rules. **Chaos Mesh** and **Litmus** are real, best-in-class Kubernetes chaos *platforms*, but installing a CRD-based controller + admission webhook + dashboard into R15's `kind` clusters is disproportionate machinery for the two K8s-based scenarios R15 needs (matching R13's own precedent of using plain `kubectl`/`stress-ng`/policy edits instead of a chaos platform for its own K8s scenarios).

**Final toolset for R15: zero new tools.** Toxiproxy, `docker kill`/`pause`/`network disconnect`, `stress-ng`, `kubectl patch`/`exec`, and the Kafka Connect/Cilium/Patroni/Valkey APIs already used throughout R4-R14 — composed into multi-fault sequences by thin new orchestration scripts (the only new code this phase needs, following R13's own `inject.sh` precedent).
