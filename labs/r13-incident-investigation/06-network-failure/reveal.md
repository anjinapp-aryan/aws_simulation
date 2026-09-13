# R13-06 — SPOILER — ROOT CAUSE

## What was injected
`inject.sh` deployed `backend-v2` (`manifests/05-backend-v2.yaml`) — a real second backend replica sharing `app: backend` (so the `backend` Service genuinely load-balances real traffic to it) but with a **label typo**: `tier: backend-v2` instead of `tier: backend`.

## Real observed evidence
- `evidence/connectivity.txt`: the original backend pod (`tier=backend`) → database: **ALLOWED**. The new `backend-v2` pod (`tier=backend-v2`) → database: **DENIED (timed out)** — same Service, same intended function, different real outcome.
- `kubectl get pods --show-labels` shows the label difference directly.
- Real Hubble flow data (`evidence/hubble-flows.txt`): DNS (`coredns:53`) is `EGRESS ALLOWED`/`FORWARDED` for `backend-v2` — DNS itself is fine, ruling out a cluster-wide DNS problem (the R12-07 failure mode) — but `backend-v2 -> database:5432` shows `policy-verdict:none EGRESS DENIED` / `Policy denied DROPPED (TCP Flags: SYN)`, repeated on every retry.

## Root cause
The existing `NetworkPolicy` objects (`allow-backend-to-database` / `allow-backend-egress-to-database` in `manifests/03-allow-least-privilege.yaml`) select on `podSelector: { matchLabels: { tier: backend } }`. `backend-v2`'s pods carry `tier: backend-v2` (a typo introduced when this "new" replica was rolled out) — a value that does not match the selector at all, so under the cluster's real default-deny posture (`01-default-deny.yaml`), this pod has **zero** egress allow rules to the database. Since the Service still load-balances real traffic to it (it shares `app: backend`), **some fraction of backend traffic silently fails** depending purely on which pod a request happens to land on — the exact intermittent symptom reported, now root-caused to a label mismatch rather than a flaky network.

## Immediate mitigation
Relabel the pod (fix its `tier` to `backend`, or scale it to 0 and roll back) — `fix.sh`.

## Permanent fix / prevention
- CI/admission-time validation that a new Deployment's pod-template labels match every NetworkPolicy selector already governing that namespace/Service, before it's allowed to roll out.
- Prefer selecting NetworkPolicies (and Services) on a single stable identity label (e.g. `app: backend`) rather than a second, easily-typo'd label (`tier`) that must be kept in sync by hand across every manifest.

## AWS mapping
A new ASG launch template or ECS task definition that didn't carry over the correct Security Group / tag used by an existing SG rule — new instances silently lack network access that otherwise-identical existing instances have. Directly reuses R12's already-proven real Cilium/NetworkPolicy enforcement and Hubble flow visibility unmodified.
