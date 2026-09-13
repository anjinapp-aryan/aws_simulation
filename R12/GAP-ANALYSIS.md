# R12 Gap Analysis

## 1. What R1-R11 have already demonstrated
| Phase | Concept |
|---|---|
| R1 | IAM/task credentials |
| R2 | ALB routing/health |
| R3 | Container lifecycle |
| R4 | DB connectivity/pooling |
| R5 | CPU/mem pressure, observability |
| R6 | Caching/failover |
| R7 | Async messaging/DLQ |
| R8 | Distributed tracing |
| R9 | Circuit breaking (Envoy: routing/resilience, not security) |
| R10 | Kubernetes orchestration (scheduling, self-healing, HPA - **no network security tested**) |
| R11 | Distributed transactions (Outbox/CDC/Saga) |

## 2. What is still theoretical / entirely missing
Every phase so far assumes services can freely talk to each other over the network - **nothing has ever tested or enforced who is ALLOWED to talk to whom.** R10 deployed a real Kubernetes cluster with zero NetworkPolicies (the default in vanilla `kind` is "allow all" - any pod can reach any other pod). R9's Envoy handled circuit-breaking and outlier detection but never authentication/authorization between services. No phase has touched encryption-in-transit between internal services, service identity, or the "assume breach, verify every request" zero-trust model that is now standard EKS/Architect-interview material.

## 3. Candidate topics, ranked

| Candidate | R1-R11 coverage | Senior/Architect value | Hands-on | Visualization | $0 | Priority |
|---|---|---|---|---|---|---|
| **Kubernetes network security / zero-trust (NetworkPolicies + mTLS + real flow observability)** | **None** | **VERY HIGH** | **VERY HIGH** | **VERY HIGH (Hubble)** | **Yes** | **VERY HIGH** |
| Secrets management (Vault, dynamic DB credentials, rotation) | Partial (R4/R11 use static creds) | HIGH | HIGH | MEDIUM (Vault UI) | Yes | HIGH |
| Chaos-engineering-as-code (Chaos Mesh declarative experiments vs our ad-hoc scripts) | Partial (every phase does manual fault injection) | HIGH | HIGH | HIGH | Yes | HIGH |
| API Gateway / rate limiting | Trivial delta over R2/R9's Traefik/Envoy work | MEDIUM | LOW novelty | LOW novelty | Yes | LOW |
| Multi-region / DR | None | HIGH (conceptually) | LOW (fidelity ceiling) | LOW | Partial | LOW |

## 4. Recommended R12 topic
**Kubernetes network security and zero-trust**: NetworkPolicy enforcement (default-deny, then explicit allow rules) plus real encrypted service-to-service traffic, observed live via a real network-flow visualization tool - directly extending R10's existing `kind` cluster rather than building new infrastructure.

## 5. Why this wins
- **Largest pure gap**: literally zero security enforcement has been tested anywhere in R1-R11 at the network layer - every prior phase's services could always reach each other freely.
- **Directly extends R10** rather than building new infrastructure - same `kind` cluster, same app pattern, new CNI-level capability.
- **Very high interview value**: "how do you implement least-privilege networking in EKS", "explain zero-trust for microservices", "what's the difference between a Security Group and a NetworkPolicy" are standard Staff/Architect questions this project has not yet earned the right to answer from experience.
- **Exceptionally strong visualization candidate**: Cilium's Hubble gives a real, live, graphical flow map showing exactly which connections are allowed/denied in real time - arguably the best visualization fit of any phase so far, and no custom UI is remotely needed.
- **$0 and fully local**: Cilium runs entirely inside the existing `kind` cluster.

## 6. Why other candidates were not selected
- Secrets management: real and valuable, but a narrower, more self-contained gap that doesn't require extending R10's cluster - queued as a strong R13 candidate.
- Chaos-engineering-as-code: legitimate methodology gap (we've always used ad-hoc scripts, never a declarative chaos-experiment framework), but overlaps significantly with fault-injection mechanics already proven across R1-R11; lower marginal learning value than a completely untested security dimension.
- API Gateway/rate limiting, Multi-region/DR: both previously deprioritized in R10/R11's own gap analyses for the same reasons (low novelty / low local fidelity respectively) - still true here.
