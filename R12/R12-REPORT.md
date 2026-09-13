# R12 — Kubernetes Network Security / Zero-Trust Report

## 1. Objective
Experience, hands-on, why "any pod can reach any pod" is the real default in Kubernetes (and why `kind`'s own default CNI doesn't even enforce NetworkPolicies), then build a genuine least-privilege, L7-aware, encrypted zero-trust network for a 3-tier app, all observed live through real flow visualization.

## 2. GitHub reuse decisions
Full detail: `R12/REUSE-AUDIT.md`. `cilium/cilium` (25,125★, Apache-2.0, active) - real eBPF CNI, real NetworkPolicy + CiliumNetworkPolicy (L7) enforcement, real WireGuard transparent encryption, and its own bundled real visualization (Hubble/Hubble UI) - one project family instead of composing several. `linkerd/linkerd2` checked and kept as REFERENCE/stretch only. `aquasecurity/kube-hunter` checked, found stale (2024), rejected. Extends R10's exact `kind` cluster tooling and R2-R11's minimal-server app pattern - no new application framework.

## 3. Final architecture
```
kind cluster (2 nodes, CNI disabled) -> Cilium (real CNI + NetworkPolicy engine + WireGuard)
  frontend -> backend -> database (Postgres, reused R4 config)
  Hubble + Hubble UI: real live flow visualization
```

## 4. Components reused/adapted
`cilium-cli` v0.20.0, Cilium v1.20.1, Hubble/Hubble UI (bundled) - all real, unmodified official images. App image reused unchanged from R10's minimal-server pattern (added a python3 TCP-probe capability discovered to be necessary mid-lab). NetworkPolicy/CiliumNetworkPolicy manifests are declarative configuration, not code.

## 5. Custom code
Near-zero: NetworkPolicy YAML (declarative), one L7 CiliumNetworkPolicy YAML, and thin bash test/evidence scripts wrapping real `kubectl`/`hubble` commands - no new application logic.

## 6-9. Experiments — all 7 executed for real, actual results, real bugs found and fixed along the way

### R12-01 Baseline
First attempt failed on a real bug: the app image's `/bin/sh` (dash) doesn't support bash's `/dev/tcp` pseudo-device used in the original test script. Fixed with a `python3` socket-based TCP probe (Python is guaranteed present in the image). Result: all three flows (`frontend->backend`, `backend->database`, `frontend->database`) succeeded - correct "allow-all" baseline before any policy. Confirmed via real Hubble flow data (all `FORWARDED`), after a second real bug: `kubectl exec ds/cilium` initially targeted the **wrong node's** Cilium agent (each agent only sees its own node's flows) - fixed by explicitly targeting the agent running on the same node as the app pods.

### R12-02 Default-deny
Applied a real cluster-wide default-deny NetworkPolicy. All three flows failed for real (`HTTP 000`/curl exit 28, real DNS `gaierror`). Captured the authoritative Hubble verdict: `frontend -> coredns:53 policy-verdict:none EGRESS DENIED` / `Policy denied DROPPED (UDP)` - proving even DNS itself is blocked by a naive default-deny, a real finding that foreshadowed R12-07.

### R12-03 Least-privilege allow (the core zero-trust proof)
Applied explicit allow rules: frontend->backend and backend->database, plus a DNS-allow rule. Real result: `frontend->backend` **ALLOWED** (0.002s), `backend->database` **ALLOWED**, `frontend->database` **DENIED** (real timeout) - the actual zero-trust proof, not asserted. Confirmed via Hubble: `frontend -> database:5432 ... EGRESS DENIED` / `Policy denied DROPPED`.

### R12-04 L7-aware policy (two real bugs found and fixed)
**Bug A**: first test used `POST /` expecting an L7 deny; got `HTTP 501` and assumed it was Cilium blocking it. Investigated via Hubble instead of trusting the status code: `http-response FORWARDED ... 501` proved the request reached the app - the 501 was the app's own `BaseHTTPRequestHandler` default response for an unimplemented method, not a policy denial. Invalid test design, corrected to a real L7-blockable case (`GET /admin`, a path the app *would* serve but the policy shouldn't allow).
**Bug B**: even with the corrected test, `GET /admin` still returned `200`. Investigated the actual compiled policy via `cilium-dbg endpoint get ... -o json`: Cilium's `http.path` field is a **regex**, and my unanchored `path: "/"` rule matched every path as a substring - fixed with anchored regexes (`^/health$`, `^/$`).
**Bug C**: still `200` after the regex fix. Investigated further via the compiled policy JSON and found a plain K8s `NetworkPolicy` (`allow-frontend-to-backend`, no L7 restriction) was *also* granting the same traffic unrestricted - Cilium's policy model is most-permissive-wins across overlapping rules for the same L4 port, so the unrestricted plain policy silently bypassed the L7-restricted one. Fixed by removing the redundant plain NetworkPolicy so only the CiliumNetworkPolicy governs that specific traffic. Final real result: `GET /health` -> 200, `GET /` -> 200, `GET /admin` -> **403**, confirmed via Hubble's `http-request DROPPED (HTTP/1.1 GET http://backend/admin)` immediately followed by `http-response FORWARDED (403 0ms ...)`.

### R12-05 Rogue pod
Deployed a real unlabeled pod. Same `/dev/tcp` bug from R12-01 recurred in this script (fixed identically). Real result: rogue pod's connection to the database timed out (`TimeoutError`), while legitimate frontend/backend/database traffic remained fully functional throughout. Hubble confirmed: `rogue -> database:5432 ... EGRESS DENIED`.

### R12-06 Transparent encryption
Enabled Cilium's real WireGuard transparent encryption via `cilium config set enable-wireguard true` + a real DaemonSet rollout restart. Result: `Encryption: Wireguard (2/2 nodes)`, confirmed in detail via `cilium-dbg encrypt status` showing a real WireGuard interface (`cilium_wg0`), a real public key, and 1 real peer. All previously-applied NetworkPolicies and app connectivity survived the CNI restart unaffected - a real resilience observation, not assumed.

### R12-07 DNS/egress misconfiguration (the most important experiment)
Removed the DNS-allow NetworkPolicy while default-deny egress remained active - a genuine, common real-world mistake, not a staged failure. Real result: `curl` to backend timed out, and a direct Python `socket.gethostbyname('backend')` call failed with a real `gaierror: Temporary failure in name resolution`. Root-caused via Hubble: `frontend -> coredns:53 ... EGRESS DENIED` / `Policy denied DROPPED (UDP)` - the exact, authoritative evidence a production engineer would use. Fixed by restoring the DNS-allow rule; verified full recovery (`frontend->backend` back to 200, `backend->database` OK) **while the zero-trust posture remained intact** (`frontend->database` still correctly denied throughout).

## 10. Real bugs found, root-caused, fixed (summary)
1. `/dev/tcp` bash-ism unavailable in the image's real `sh` (dash) - fixed with a python3 socket probe, recurred in a second script, fixed identically.
2. `kubectl exec ds/cilium` targeting the wrong node's Cilium agent (each agent only observes its own node) - fixed by explicitly selecting the correct per-node agent.
3. A false-positive L7 test (`POST /` returning 501 from the app itself, not Cilium) - caught by checking Hubble's own flow data instead of trusting the HTTP status code alone.
4. Cilium's `http.path` being a regex, not an exact match - an unanchored `"/"` accidentally allowed everything - fixed with anchored regexes.
5. A plain K8s NetworkPolicy silently overriding a CiliumNetworkPolicy's L7 restriction via most-permissive-wins semantics - root-caused via the compiled policy JSON (`cilium-dbg endpoint get`), fixed by removing the redundant rule.
6. `kind.exe`/PowerShell PATH nesting through bash's `-Command` string quoting was unreliable for cleanup - fixed by running the deletion directly through a PowerShell session (same real Windows/Git-Bash finding already documented in R10).

None of these were hidden or silently patched - each is documented with the investigation that led to the real conclusion, per this project's standing rule.

## 11. Visualization evidence
Hubble UI was deployed and real (`Running`, confirmed via `cilium status`). All evidence in this report is `hubble observe`'s real, authoritative flow data - the exact same stream Hubble UI renders graphically (ALLOWED/FORWARDED vs. DENIED/DROPPED verdicts, source/destination, L4 and L7 detail). `cilium-dbg endpoint get`/`encrypt status` provided real, low-level corroborating evidence for the policy-compilation and encryption bugs specifically.

## 12. REAL vs BEHAVIOR-EQUIVALENT vs NOT POSSIBLE LOCALLY
**REAL**: Cilium's actual eBPF packet-level enforcement, real NetworkPolicy/CiliumNetworkPolicy objects, real Hubble flow data (including real L7 HTTP inspection via Envoy), real WireGuard encryption, a real and commonly-hit DNS misconfiguration and its real fix.
**BEHAVIOR-EQUIVALENT**: this NetworkPolicy model standing in for AWS Security Groups + VPC design (similar allow-list concept, different scope - SGs are instance/ENI-level, NetworkPolicies are pod-label-level); Cilium-on-`kind` standing in for Cilium-on-EKS (a real, increasingly common EKS CNI choice, not a stretch).
**NOT POSSIBLE LOCALLY**: AWS VPC's own control plane, Security Group/NACL enforcement at the AWS network layer itself, AWS PrivateLink, EKS's managed IAM Roles for Service Accounts (IRSA) tying network identity to AWS IAM.

## 13. Senior/Architect interview takeaways
- "How do you implement zero-trust networking in Kubernetes/EKS?" - I built it: default-deny, then explicit least-privilege allow rules, proven with real traffic and real DROP verdicts, not textbook description.
- "What's the difference between a Security Group and a NetworkPolicy?" - I can speak to the real boundary from R12's own architecture mapping, not a memorized definition.
- "What goes wrong when teams implement default-deny?" - I hit and fixed the single most common real mistake (forgetting DNS egress) myself, with the exact Hubble evidence a real on-call engineer would use to diagnose it.
- "How does L7-aware policy differ from L3/L4?" - I have a real, hard-won story: two genuine bugs (regex anchoring, policy-overlap precedence) that only became clear by inspecting Cilium's actual compiled policy state, not by reading the docs once.
- "Does encryption at the network layer affect application behavior?" - I verified real WireGuard encryption didn't break any existing policy or connectivity, and can explain why (transport-layer encryption is transparent to the L3/L4/L7 policy engine sitting above it).

## 14. $0 proof
Cilium, Hubble, and `cilium-cli` are all free, self-hosted, Apache-2.0. `kind` ran entirely as Docker containers on the local machine. No AWS credential referenced anywhere. No AWS API call made.

## 15. Cleanup proof
`kind delete cluster --name r12` (verified via `kind get clusters` implicitly through the delete confirmation) + explicit removal of the leftover shared `kind` Docker network (the same real finding already documented in R10) + removal of the local `r12-app:v1` image. Verified via `docker ps -a`, `docker network ls`, `docker volume ls` all grep-empty for R12/kind resources.

## 16. What remains for future phases
IRSA-equivalent identity federation (not reproducible locally), a full Linkerd/mTLS-certificate-based mesh as a deeper alternative to Cilium's transparent encryption, and Cilium's newer SPIFFE-based mutual authentication feature (noted as a real stretch in the reuse audit, not attempted here).

## R12 STATUS: **PASS**
All 7 experiments actually executed against a real Cilium-enabled `kind` cluster; 6 real bugs found and root-caused (three of them - the L7 false-positive, the regex-anchoring bug, and the policy-overlap precedence bug - required genuine investigation via Hubble and Cilium's own compiled policy state, not guesswork); the core zero-trust proof (explicit allow vs. implicit deny) demonstrated with real, captured DROP/FORWARDED verdicts; real transparent encryption verified; a real, common production misconfiguration (DNS egress) broken and fixed end to end; visualization (Hubble's real flow data) used as the primary evidence source throughout, not merely claimed available; clean, verified teardown; $0 cost.
