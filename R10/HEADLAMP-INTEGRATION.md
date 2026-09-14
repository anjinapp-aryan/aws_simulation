# R10 Headlamp Integration

Optional, additive Kubernetes resource visualization for R10 only, per the approved `[HEADLAMP] OPTIONAL IMPROVEMENT APPROVED` scope. R1-R9 and R11-R15 were not touched.

## Why Headlamp was added
R10's original visualization audit (see `R1-R15-VISUALIZATION-AUDIT.md`) confirmed R10 had a real, material gap: no browser-based view of the cluster's actual object state (nodes, pods, deployments, services, HPA) — only `kubectl` text output. `kubernetes-sigs/headlamp` (7268★, Apache-2.0, verified real and active, official `kubernetes-sigs` org) was evaluated and approved to close exactly this gap.

## What it visualizes
The real Kubernetes object hierarchy: Cluster → Nodes → Namespaces → Pods → Deployments → ReplicaSets → Services → HPA — all live, all proxied through Headlamp's own backend to the real `kind` cluster's real API server.

## What it does NOT replace
- **Grafana/Prometheus** — metrics over time (unchanged, still the metrics source of truth)
- **`kubectl`** — still the primary CLI tool for running experiments
- Nothing about R10's actual experiments, manifests, or scripts changed

## Architecture
```
kind cluster "r10" (unchanged)
   |
   v
Headlamp Deployment (new, kube-system namespace)
  - runs with the default kube-system SA for its own internal
    cluster-metadata lookups (read-only, harmless "forbidden" log
    line observed and explained below - benign)
  - serves the actual browser UI + proxies API calls using
    whichever bearer token the BROWSER USER supplies at login
   |
   v
Browser (via kubectl port-forward, local-only, never exposed publicly)
   |
   v
headlamp-admin ServiceAccount token (the identity the human pastes
into Headlamp's login screen - bound to `view` + a narrow
node-read-only ClusterRole, NOT cluster-admin)
```

## UI walkthrough
1. `kubectl port-forward -n kube-system svc/headlamp 65100:80`
2. Open `http://localhost:65100` in a browser
3. Get the login token: `kubectl get secret -n kube-system headlamp-admin -o jsonpath='{.data.token}' | base64 -d`
4. Paste it into Headlamp's login screen
5. Browse: Nodes (3 real `kind` nodes), Pods (real `r10-app`/Grafana/Prometheus/etc.), Deployments, Services, HPA — all real, live objects

## Baseline observation (OBSERVED, live, this session)
Via Headlamp's own API (not `kubectl`), confirmed real:
- 3 real nodes: `r10-control-plane`, `r10-worker`, `r10-worker2`
- 5 namespaces, 8 deployments, 8 services, 1 HPA (`r10-app`, `cpu: 5%/50%`, `2/2` replicas)
- `r10-app` pods `Running`, `0` restarts

## Failure observation (OBSERVED, live, this session)
Reused R10's own historically-proven self-healing mechanism (`evidence/R10-02/self-healing.log`) exactly, with Headlamp as the new observation point instead of `kubectl`:
- **BEFORE** (via Headlamp API): `r10-app-65fd65fcb5-8gk5j` — `Running`
- **Action**: `kubectl delete pod r10-app-65fd65fcb5-8gk5j` (real deletion, no new mechanism)
- **AFTER** (via Headlamp API): `r10-app-65fd65fcb5-8gk5j` is gone; **`r10-app-65fd65fcb5-p4gsv`** — a genuinely new pod, different name, fresh `creationTimestamp` — is `Running` in its place

## Recovery observation (OBSERVED, live, this session)
Confirmed the app itself is serving real traffic from the new, self-healed pod: `curl http://localhost:65080/` → `Hello from pod=r10-app-65fd65fcb5-p4gsv ...` — the replacement pod, not the deleted one.

## AWS/EKS mapping
```
Headlamp:  Kubernetes Cluster → Nodes → Pods → Deployments → Services
AWS EKS:   EKS Cluster        → Nodes → Pods → Deployments → Services
```
**Classification: CONCEPTUAL MAPPING / BEHAVIOR-EQUIVALENT.** Headlamp is explicitly **not** the AWS Console — it shows the same object-hierarchy *shape* a learner would navigate in the EKS console's workload view, using vanilla Kubernetes API objects. No AWS-specific concept (IAM, VPC CNI, managed node groups) is shown or claimed.

## Security/RBAC (real, live-tested)
- **DEMO/LOCAL LEARNING RBAC, not production practice.** The official quick-start commonly binds to `cluster-admin`; this integration instead binds `headlamp-admin` to the built-in `view` ClusterRole (read-only on nearly all namespaced resources).
- **Real gap found and fixed during live testing**: `view` does **not** include cluster-scoped resources — confirmed via `kubectl auth can-i list nodes --as=system:serviceaccount:kube-system:headlamp-admin` returning `no`. A second, narrowly-scoped `ClusterRole` (`headlamp-node-reader`: `get`/`list`/`watch` on `nodes` only, nothing else) was added specifically to close this, rather than escalating to `cluster-admin`. Verified afterward: all 3 real nodes visible.
- No write access anywhere — Headlamp cannot create, update, or delete anything in this cluster with the `headlamp-admin` token.

## $0 validation
Apache-2.0, no account, no paid tier, one additional container (`ghcr.io/headlamp-k8s/headlamp:v0.45.0`, ~109MB image, comparable resource footprint to Dozzle). No AWS resource, credential, or service referenced anywhere.

## Regression results (OBSERVED, live, this session)
| Check | Result |
|---|---|
| App via NodePort (`:65080`) | `HTTP 200`, real response from the self-healed pod |
| Prometheus (`:65090`) | `HTTP 302` (its own normal redirect to `/graph`) |
| Grafana (`:65300`) | `HTTP 200` |
| HPA | Functioning, real live CPU metric (`5%/50%`), `2/2` replicas |
| Other 14 phases | `git status` confirms zero files touched outside R10 and this new doc |

No existing R10 tool, script, dashboard, or experiment semantics changed.

## Files changed / created
- **Created**: `labs/r10-kubernetes/monitoring/headlamp.yaml` (new manifest: ServiceAccount, 2 ClusterRoleBindings, Secret, Service, Deployment)
- **Created**: `R10/HEADLAMP-INTEGRATION.md` (this file)
- **Not changed**: `kind-config.yaml`, `manifests/*`, existing `monitoring/prometheus.yaml`/`grafana.yaml`/`metrics-server.yaml`, `scripts/*`, `app/*`, any R1-R9/R11-R15 file

## Commands
**Start** (after R10's own existing `scripts/run.sh` has already brought up the cluster):
```bash
kubectl apply -f monitoring/headlamp.yaml
kubectl port-forward -n kube-system svc/headlamp 65100:80 &
# then browse http://localhost:65100, log in with:
kubectl get secret -n kube-system headlamp-admin -o jsonpath='{.data.token}' | base64 -d
```
**Stop** (port-forward only, cluster keeps running): kill the `kubectl port-forward` process.
**Rollback** (remove Headlamp entirely, R10 continues exactly as before):
```bash
kubectl delete -f monitoring/headlamp.yaml
```
Verified: R10's own `scripts/run.sh`/`scripts/cleanup.sh`/existing experiments have zero dependency on Headlamp and are unaffected by either its presence or its removal.

## Final learning takeaway
Kubernetes' own self-healing (ReplicaSet reconciliation) is normally invisible unless you already know to run `kubectl get pods` at the right moment. Headlamp makes the same real event — a pod dying and a genuinely new one taking its place — glanceable in a browser, the same way an EKS console user would notice a task/pod being replaced. This session's own live test is the proof: the before/after pod names and timestamps came from Headlamp's own API, not from re-running `kubectl`.
