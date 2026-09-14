# Optional Kubernetes UI Improvement Audit — Headlamp for R10/R12/R14/R15

**Evaluation only. Nothing installed, nothing modified.**

---

## 1. Current-state audit (re-confirmed from this session's own direct build/audit experience)

### R10 — currently visible via:
- `kubectl get pods/deployments/svc/hpa` — real, but text-only, no persistent browser view
- `metrics-server` — feeds HPA math, no UI of its own
- No browser UI shows pod restarts, rollout progress, or replica topology visually

### R12 — currently visible via:
- **Hubble UI** — real, excellent, shows live network flows (ALLOW/DENY, L3-L7) — this is the phase's real strength
- `kubectl get networkpolicy/ciliumnetworkpolicy` — text only
- No browser view of the underlying pod/namespace/label structure that the policies actually select against

### R14 — currently visible via:
- `patronictl list` — real, authoritative, text table (leader/replica/lag/timeline)
- `pgbackrest info`, `velero backup describe` — text
- Grafana (if the community Patroni dashboard were imported — not currently done)
- Runs in plain **Docker Compose**, not Kubernetes — Headlamp is not applicable to R14's Patroni cluster itself. R14's own `dr-drill/` sub-lab *does* use a `kind` cluster for the Velero DR experiment specifically.
- No browser view of Postgres pod topology (n/a for the Compose part; applicable only to the DR-drill's `kind` portion)

### R15 — currently visible via:
- Inherits Grafana/Jaeger/Dozzle/Hubble/Kafka UI/RabbitMQ UI from the composed R4-R14 stack
- Entirely Docker Compose, no `kind` cluster in the standing system (by deliberate Phase A design choice, to avoid the cross-network fragility R14 hit) — **Headlamp has no cluster to attach to in R15's current architecture**

## 2. Actual visualization gap

**Confirmed real** for R10 and the K8s-object side of R12: no persistent, glanceable, browser-based view of "what pods/deployments/services actually exist right now and what state are they in." `kubectl` output is functional but requires re-running a command and re-reading text every time state changes — there's no dashboard you can just glance at mid-experiment to see a rollout progressing or a pod restarting.

**Does this materially affect learning?** Moderately, specifically for R10's rolling-update and HPA scale-out/in experiments, where *watching a number change over time* (replica count climbing/falling) is the whole point — a live visual counter is a genuinely better learning aid than re-running `kubectl get pods` every few seconds. For R12, the gap is smaller: Hubble UI already gives the primary "what matters" view (is traffic ALLOWED or DENIED); a pod/namespace browser would be a secondary, supporting view at best.

**Not a gap for R14/R15**: Headlamp is inapplicable to R14's Compose-based Patroni cluster and to R15's Compose-only standing system. It's only relevant to R14's separate `kind`-based DR-drill sub-lab, and even there only for viewing the Postgres Deployment/PVC objects Velero backs up — a minor, not central, use case.

## 3. Headlamp GitHub/license/activity audit (verified this session, real API calls)

| Check | Result |
|---|---|
| Repository | `kubernetes-sigs/headlamp` |
| License | **Apache-2.0** — verified by fetching the actual `LICENSE` file, not just the badge |
| Stars | 7268 |
| Archived | No |
| Last push | 2026-09-11 (within days of this audit) |
| Latest release | v0.45.0, published 2026-08-20 |
| Governance | Recently moved under **Kubernetes SIG UI**, repo now lives in the official `kubernetes-sigs` GitHub org — a real, meaningful maturity/trust signal, not just a star count |
| Open issues | 1419 (normal for an actively-maintained project of this size, not a red flag by itself) |
| Security posture | Carries an OpenSSF Best Practices badge and OpenSSF Scorecard — real, verifiable signals of project health |
| Deployment options | In-cluster (Deployment + Service, the natural fit for `kind`) or desktop app |
| Docker support | Yes — official container images at `ghcr.io` |
| Local-only operation | Yes — works entirely against a local kubeconfig, no external service required |
| Paid service / account | **None required** |
| RBAC | Uses standard Kubernetes RBAC + a ServiceAccount token for access — same mechanism `kubectl` itself uses, nothing new to learn |

## 4. Headlamp technical fit — per phase

### R10
Can show: cluster, nodes, pods, deployments, replica count, pod status/restarts, services, rollout progress. **Yes, directly and well** — this is exactly Headlamp's core, intended use case (it explicitly bills itself as a "traditional Kubernetes dashboard" feature set). HPA visibility: Headlamp can show the `HorizontalPodAutoscaler` object and its current/desired replica fields, though not a live graph the way Grafana would.

### R12
Can complement Hubble by showing pods/namespaces/services/NetworkPolicy objects and their raw configuration. **Yes, as a secondary view.** Headlamp must NOT and does not attempt to replace Hubble — it has no concept of live network flow data; it only shows the *declared* policy object, not the *enforced* traffic decision. Hubble remains the only tool that shows ALLOW/DENY in real time.

### R14
Applicable only to the DR-drill's `kind` sub-cluster, and only for viewing the Postgres `Deployment`/`PersistentVolumeClaim` objects Velero backs up — a minor, supporting use case. **Not applicable** to the main Patroni-in-Compose cluster (no Kubernetes there to view).

### R15
**Not applicable** — the standing system is Compose-only by deliberate design; there is no cluster for Headlamp to attach to.

## 5. Visualization role matrix (no duplication)

| Tool | Role |
|---|---|
| Headlamp (if added) | Kubernetes resource/control-plane object view — "what exists, what state is it in" |
| Grafana | Metrics over time |
| Dozzle | Container logs |
| Jaeger | Distributed traces |
| Hubble/Hubble UI | Real-time network/security flow decisions (ALLOW/DENY) |
| Kafka UI | Kafka topic/consumer-group state |
| RabbitMQ UI | Queue/consumer state |
| `patronictl` | Database HA cluster state (leader/replica/lag) |
| pgweb | Actual database row data |

No overlap: Headlamp would show the *Kubernetes object graph*, a layer nothing else currently shows at all.

## 6. $0 / resource evaluation

- **$0 LOCAL, OPEN SOURCE** — confirmed, Apache-2.0, no account, no paid tier, no external service.
- **Resource overhead**: Headlamp's backend is a small Go binary; its frontend is a static React bundle served by that same backend. Comparable in footprint to Dozzle or a single Grafana instance — materially smaller than Prometheus or Jaeger, which this project already runs in every phase without issue. Expected to add roughly the same order of magnitude of RAM/CPU as one more Dozzle-sized container, not a meaningful burden on a machine already running a full `kind` cluster plus Cilium/Hubble.

## 7. Decision Matrix

| Criterion | Current R10/R12/R14/R15 | Headlamp | Winner |
|---|---|---|---|
| Kubernetes resource visibility | `kubectl` text | Live browser view | **Headlamp** |
| Node visibility | `kubectl get nodes` | Live browser view | **Headlamp** |
| Pod visibility | `kubectl get pods` | Live browser view | **Headlamp** |
| Deployment visibility | `kubectl get deploy` | Live browser view | **Headlamp** |
| Service visibility | `kubectl get svc` | Live browser view | **Headlamp** |
| HPA visibility | `kubectl get hpa` | Live browser view (object state, not a graph) | Tie (Headlamp slightly better for glanceability) |
| Network policy visibility | `kubectl get networkpolicy` + Hubble (enforcement) | Object view only (no enforcement data) | **Existing (Hubble) for enforcement; Headlamp adds object view** |
| Metrics | Grafana | none | **Existing (Grafana)** |
| Logs | Dozzle | basic pod logs (Headlamp has this too, but Dozzle already covers it) | **Existing (Dozzle)** |
| Traces | Jaeger | none | **Existing (Jaeger)** |
| Network flows | Hubble UI | none | **Existing (Hubble)** |
| HA/DR visibility | `patronictl`/`pgbackrest info`/`velero describe` | none (Compose-based, out of scope) | **Existing** |
| Beginner friendliness | Requires knowing `kubectl` syntax | Point-and-click, self-explanatory | **Headlamp** |
| AWS Console mental model | None currently | Cluster→Nodes→Pods→Deployments→Services tree, similar shape to EKS console's workload view | **Headlamp** |
| $0 | Yes | Yes | Tie |
| Local operation | Yes | Yes | Tie |
| Integration complexity | n/a | Low — one Deployment+Service against an existing kubeconfig | **Existing** (nothing to integrate) but Headlamp's own complexity is low |
| Maintenance burden | None (already there) | Low (occasional image tag bump) | **Existing**, but Headlamp's burden is minor |

## 8. Learning value score (0-5)

| Phase | Score | Reasoning |
|---|---|---|
| R10 learning value | **4** | Directly closes a real, confirmed gap — rollout/replica-count/restart visibility |
| R12 learning value | **2** | Secondary/supporting only; Hubble already covers the core lesson |
| R14 learning value | **1** | Only touches the minor DR-drill sub-cluster, not the main lab |
| R15 learning value | **0** | Not applicable — no cluster exists in the standing system |
| AWS mental-model similarity | **4** | Genuinely close shape to the EKS console's workload view |
| Beginner memorability | **4** | Point-and-click browsing is easier to remember than `kubectl` flag syntax |
| Troubleshooting usefulness | **3** | Useful for "what's the current state," but Hubble/Grafana/Jaeger remain the tools that actually diagnose *why* |
| **Overall** | **~2.6/5**, driven almost entirely by R10 | Worthwhile specifically for R10, marginal elsewhere |

## 9. Risk / complexity assessment

- **Risk to existing experiments**: none identified — Headlamp is a read/write viewer sitting alongside the cluster, not a component any existing script or manifest depends on. Removing it later has zero effect on anything else.
- **Complexity added**: low — one Deployment + Service (or the project's existing NodePort convention), pointed at the cluster's own in-cluster ServiceAccount; no changes needed to any existing manifest, script, or compose file.
- **Maintenance burden**: low — occasional image-tag bump, same category of upkeep as any other pinned-version tool already in this project (e.g., `envoyproxy/envoy:v1.31-latest`, `jaegertracing/all-in-one:1.60`).

## 10. AWS Mapping

```
Headlamp:  Kubernetes Cluster → Nodes → Pods → Deployments → Services
AWS EKS:   EKS Cluster        → Nodes → Pods → Deployments → Services
```

Classification: **CONCEPTUAL MAPPING / BEHAVIOR-EQUIVALENT** — Headlamp shows the same *object hierarchy* a learner would navigate in the EKS console's workload view. It is explicitly **not** claimed to be the AWS Console itself, and it shows vanilla Kubernetes API objects, not any AWS-specific concept (no IAM, no VPC CNI specifics, no EKS-managed node group details) — those remain **NOT POSSIBLE LOCALLY** regardless of which K8s UI is used.

## 11. Final Decision

**2. OPTIONAL REUSE HEADLAMP — for R10 only, as a genuinely optional addition. NO CHANGE for R12 (Hubble already sufficient), R14 (inapplicable to the main lab), R15 (inapplicable, no cluster).**

- **Exactly which phases benefit**: R10 (real, moderate benefit). R12 gets a minor, optional bonus if added there too since the same cluster type is used, but is not the justification on its own. R14's DR-drill sub-cluster could optionally use it for the same minor reason. R15 gets nothing (no cluster).
- **What the learner will see**: a live, browser-based tree of the `kind` cluster's actual nodes, pods, deployments, replica counts, and rollout status — updating as R10's own experiments run.
- **What it complements**: `kubectl`, `metrics-server`/HPA — gives those the browser view they currently lack.
- **What it does NOT replace**: Grafana (metrics), Dozzle (logs), Jaeger (traces), Hubble/Hubble UI (network flow enforcement — R12's real strength stays exactly as-is).
- **Estimated implementation effort**: very low — one manifest, no changes to any existing file.
- **Expected resource overhead**: small, comparable to one more Dozzle-sized container.
- **$0 validation**: confirmed, Apache-2.0, no account, no paid tier.
- **Rollback approach**: `kubectl delete -f headlamp.yaml` (or simply omit applying it) — fully additive, zero coupling to any existing component.

## 12. Minimal implementation plan (NOT executed — for approval only)

```
R10:
kind cluster (already exists)
   |
   v
Headlamp Deployment + Service (new, additive)
   |
   v
Browser view: Cluster / Nodes / Pods / Deployments / Services / HPA

R12 (optional, same cluster type, low incremental cost if R10's manifest is reused as-is):
Headlamp (object view)  +  Hubble UI (flow enforcement, unchanged, primary)

R14 (optional, DR-drill sub-cluster only):
Headlamp (Postgres Deployment/PVC object view)  +  Patroni/pgBackRest/Velero (unchanged, primary)

R15: not applicable, no action
```

## 13. Rollback plan (if approved and later reconsidered)
Delete the one Headlamp Deployment/Service manifest. No other file, script, or existing component references it, so removal has zero downstream effect.

---

## Success criteria check (Section 15 of the request)
1. Meaningful visual understanding — ✅ for R10, marginal elsewhere.
2. Beginner memorability — ✅.
3. Useful AWS/EKS mental model — ✅.
4. No unnecessary duplication — ✅ (distinct role from every existing tool).
5. $0 local — ✅.
6. Does not destabilize existing experiments — ✅ (purely additive).
7. Minimal maintenance — ✅.
8. REUSE-first — ✅ (Apache-2.0, official `kubernetes-sigs` org, mature, active — no BUILD needed).

**All 8 conditions met for R10. Recommendation: optional, R10-scoped reuse; no change for R12/R14/R15 beyond the same low-cost optional bonus if desired.**

---

**STOP. Awaiting: "[HEADLAMP] OPTIONAL IMPROVEMENT APPROVED" before any installation.**
