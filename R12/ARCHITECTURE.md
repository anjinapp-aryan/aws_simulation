# R12 — Proposed Architecture (pending approval, nothing built yet)

## Diagram
```
kind cluster (EXTENDED from R10 - same 3-node setup, kindnet CNI disabled)
  |
  v
Cilium (NEW - real eBPF CNI, real NetworkPolicy enforcement, real transparent encryption)
  |
  +-- frontend pod  (existing minimal-server pattern, labeled tier=frontend)
  +-- backend pod   (existing minimal-server pattern, labeled tier=backend)
  +-- database pod  (postgres, reused R4 config, labeled tier=database)
  |
  v
NetworkPolicies (NEW - declarative YAML, default-deny + explicit allow rules)
  |
  v
Hubble + Hubble UI (NEW - bundled with Cilium, real live flow visualization)

Failure injection: an unlabeled "rogue" pod attempting unauthorized access;
                    deliberately incomplete NetworkPolicies (missing DNS/
                    egress rules) causing real, diagnosable breakage.
```

## Component classification
| Component | Status |
|---|---|
| Cilium (CNI + NetworkPolicy engine + transparent encryption) | **NEW** |
| Hubble / Hubble UI | **NEW** (bundled with Cilium, not separately built) |
| `kind` cluster | **REUSED, EXTENDED** from R10 (same tooling, CNI swapped) |
| frontend/backend app pods | **REUSED unchanged**, R2-R11 minimal-server pattern |
| database pod | **REUSED unchanged**, R4 Postgres config |
| NetworkPolicy manifests | **NEW** but declarative config, not code |

## Why this shape
- Reuses R10's cluster tooling directly instead of standing up new infrastructure.
- Three tiers (frontend/backend/database) is the smallest topology that makes a zero-trust policy meaningful - fewer than 3 tiers can't demonstrate "A can talk to B, B can talk to C, but A cannot talk to C directly."
- `kind`'s default CNI (`kindnet`) does not enforce NetworkPolicies at all (a real, confirmed limitation - `kind` itself documents this) - Cilium is installed specifically to close that gap, not merely for its own sake.

## Experiments (7)

| ID | Concept | What we do | What we SEE | Failure injection | AWS mapping | Fidelity |
|---|---|---|---|---|---|---|
| R12-01 | Baseline, no policies | Deploy 3 tiers, generate traffic frontend->backend->database | Hubble UI shows all traffic flowing freely (real "allow all" default) | — | Default VPC Security Group behavior before hardening | REAL |
| R12-02 | Default-deny | Apply a cluster-wide default-deny NetworkPolicy | Hubble UI turns every flow red/dropped in real time, app traffic fails | The policy itself is the "failure injection" | The starting point of a real zero-trust migration | REAL |
| R12-03 | Explicit least-privilege allow rules | Add policies: frontend->backend allowed, backend->database allowed, frontend->database NOT allowed | Hubble UI shows legitimate flows turn green again while a direct frontend->database attempt stays red - the actual zero-trust proof | Attempt a direct frontend->database connection (should be denied) | Security Groups / IAM least-privilege, network-segmentation design in a VPC | REAL |
| R12-04 | L7-aware policy | Restrict backend->database (or an HTTP-exposed tier) to only specific paths/methods | Hubble shows L7-level allow/deny, not just L3/L4 | A disallowed HTTP method/path from an otherwise-allowed pod | WAF/ALB listener rules operating above plain Security Groups | REAL |
| R12-05 | Unauthorized "rogue" pod | Deploy an unlabeled pod attempting to reach the database directly | Hubble shows the rogue pod's connection denied in real time | The rogue pod itself | Simulates a compromised/rogue workload in a shared VPC being contained by network policy | REAL |
| R12-06 | Transparent encryption | Enable Cilium's real WireGuard transparent encryption | `cilium status`/Hubble confirm encrypted node-to-node traffic | — | VPC traffic encryption, TLS-everywhere mandates | REAL |
| R12-07 | Real misconfiguration -> diagnose -> fix (not staged) | Apply a default-deny egress policy without an explicit DNS-allow rule (a genuine, common real-world NetworkPolicy mistake) | App breaks with real DNS resolution failures; Hubble/logs show the actual dropped DNS flow to CoreDNS; fix by adding the missing allow rule; verify recovery | The missing DNS rule itself, discovered through real investigation, not asserted in advance | The single most common real NetworkPolicy production incident | REAL |

## REAL vs BEHAVIOR-EQUIVALENT vs NOT POSSIBLE LOCALLY
- **REAL**: Cilium's actual eBPF-based packet-level enforcement, real NetworkPolicy/CiliumNetworkPolicy objects, real Hubble flow data, real WireGuard encryption, a real and commonly-hit DNS misconfiguration.
- **BEHAVIOR-EQUIVALENT**: this cluster's NetworkPolicy model standing in for AWS Security Groups + VPC design (conceptually similar allow-list model, different implementation and scope - SGs are instance/ENI-level, NetworkPolicies are pod-label-level); Cilium-on-kind standing in for Cilium-on-EKS (a real, increasingly common EKS CNI choice, not a stretch).
- **NOT POSSIBLE LOCALLY**: AWS VPC's own control plane, Security Group/NACL enforcement at the AWS network layer itself, AWS PrivateLink, EKS's managed IAM Roles for Service Accounts (IRSA) tying network identity to AWS IAM.

## $0 / resource proof
Cilium free, self-hosted, Apache-2.0. Runs inside the same 3-node `kind` cluster already proven on this machine in R10 - no additional heavy infrastructure. No AWS credential, no AWS API call.

## Cleanup strategy
`kind delete cluster` (same as R10) + `docker network rm kind` if it lingers (the same real finding already documented in R10's report) + verify via `docker ps -a`/`docker network ls`.

---

Waiting for **"R12 ARCHITECTURE APPROVED"** before writing any manifests, scripts, or code.
