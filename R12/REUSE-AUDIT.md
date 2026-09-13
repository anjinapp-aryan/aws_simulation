# R12 Reuse Audit — Kubernetes Network Security / Zero-Trust

## Searches performed (real, GitHub Search API)
| Query | Result |
|---|---|
| `kubernetes network policy local lab docker` | 0 results |
| `cilium kind zero trust demo` | 0 results |

No integrated tool exists - consistent with every prior audit. Compose mature standalone projects.

## Candidate decision table

| Component | Repository | Stars | Actual License | Activity | Decision | Reason |
|---|---|---|---|---|---|---|
| CNI + NetworkPolicy enforcement + observability | `cilium/cilium` | 25,125 | Apache-2.0 (verified) | pushed 2026-09-12, very active | **REUSE** | CNCF graduated, the real CNI increasingly used by EKS itself; provides real eBPF-based NetworkPolicy enforcement (L3/L4 **and** L7 HTTP-aware policies) AND its own real visualization tool (Hubble) in one project family - avoids composing multiple separate mesh/observability projects |
| Real-time network flow visualization | `cilium/hubble` + `cilium/hubble-ui` (ships with Cilium) | (same project family) | Apache-2.0 | active | **REUSE** | Real, live, graphical flow map - allowed vs. dropped connections shown as they happen. This is the exact visualization NetworkPolicy experiments need, and it's bundled, not a separate build |
| Service mesh mTLS (alternative/stretch) | `linkerd/linkerd2` | 11,493 | Apache-2.0 (verified) | pushed 2026-09-11, active | **REFERENCE (stretch)** | Real, simple automatic mTLS - a legitimate deeper follow-up, but Cilium's own transparent encryption (WireGuard/IPsec transport encryption between nodes) already covers the core "encrypted in transit" lesson without adding a second full project to the stack. Documented as the natural next step, not required for R12's core scope |
| Security posture scanning | `aquasecurity/kube-hunter` | 5,084 | Apache-2.0 | **stale, last push 2024-03** | **REJECT** | Investigated, found inactive; not needed for this lab's scope anyway (penetration-testing tool, not a NetworkPolicy/mesh mechanism) |
| App image, load generation | Existing R2-R11 minimal-server pattern, Vegeta | — | — | proven | **REUSE, carried forward unchanged** | No new application framework needed - NetworkPolicies act on existing pods |
| Cluster | `kind` (already used in R10) | — | — | proven | **REUSE, EXTENDED** | Same cluster tooling; Cilium replaces `kind`'s default `kindnet` CNI, which itself doesn't enforce NetworkPolicies at all (a real, documented `kind` limitation worth confirming and stating plainly, not assuming) |

## Visualization strategy
Hubble UI (bundled with Cilium) is primary - a real, live topology/flow graph showing every connection attempt as ALLOWED (green) or DENIED (red) in real time as NetworkPolicies are applied and violated. `kubectl` (`cilium status`, `hubble observe`) provides real CLI-level corroborating evidence. Grafana/Prometheus reused from R10's pattern only if Cilium's own metrics add something Hubble doesn't already show visually - not forced.

## Estimated custom code
Near-zero. NetworkPolicy manifests are declarative YAML (configuration, not code), same category as R10's Deployment/Service/HPA manifests. If any experiment needs a specific app behavior (e.g., a second "attacker" pod attempting unauthorized access), it reuses the exact minimal-server pattern from R2-R11 with no new logic beyond an identifying label.

## $0 / resource proof
Cilium is free, self-hosted, Apache-2.0. Runs inside the same local `kind` cluster already proven to work on this machine in R10 (3 nodes, modest CPU/RAM). No AWS credential, no AWS API call, no paid tier.

## What will NOT be built
No custom network-flow visualization (Hubble UI covers it), no full service-mesh control plane beyond what's needed for the security lesson (Linkerd deferred as a stretch/reference), no custom penetration-testing tooling, no new application framework.
