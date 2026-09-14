# R1–R5 FORENSIC AUDIT

## Overall Verdict

HAND-ON COVERAGE:
2 / 5 phases fully proven (R2, R4)

PARTIAL:
2 / 5 (R3, R5)

THEORY ONLY:
0 / 5

BROKEN / NON-REPRODUCIBLE:
1 / 5 (R1 — as currently committed; the underlying mechanism was proven real once manually patched)

OVERALL HANDS-ON SCORE:
83 / 100 (average of R1:58, R2:96, R3:88, R4:95, R5:77)

## Phase Verdict

**R1**: MIXED. The real mechanism (official AWS ECS credential-vending image + real MinIO IAM ALLOW/DENY enforcement) was independently re-proven live, in this session, after this audit discovered and root-caused the reason the lab currently fails out of the box: three container-executed scripts (`provision.sh`, `break-iam.sh`, `fix-iam.sh`) are corrupted with Windows CRLF line endings, causing a real dash syntax error inside the real container shell. As committed, R1 is currently **not reproducible without manual intervention** — the historical PASS evidence is genuine but not currently reproducible as-is.

**R2**: HANDS-ON PROVEN. Independently and completely reproduced live this session: real round-robin traffic, real health-check-driven 100% traffic shift on failure, real recovery — zero manual intervention required.

**R3**: MIXED (leaning strongly HANDS-ON). Self-crash→auto-restart and scaling independently reproduced live with clean, unambiguous evidence. OOM/`mem_limit` enforcement is real and fires (confirmed via `RestartCount` and a killed `exec`), but the specific `OOMKilled` flag is timing-sensitive to observe in a single check — a real Docker behavior, not a lab defect, and consistent with the project's own prior documented finding.

**R4**: HANDS-ON PROVEN. Independently and completely reproduced live this session: real connectivity, real Toxiproxy latency injection and recovery, real PgBouncer pool exhaustion via real `pgbench`, real Prometheus metric confirmation — zero manual intervention required.

**R5**: HANDS-ON PARTIALLY PROVEN. Real CPU pressure independently reproduced live. The project's own pre-existing cAdvisor bug investigation was independently re-confirmed **still accurate today** — a genuine positive signal for this project's documentation integrity. Memory-pressure, cascading-failure, and DB-latency-under-load experiments were not re-executed in this time-boxed audit and remain HISTORICALLY DOCUMENTED ONLY — not confirmed broken, simply not re-verified.

## Strongest Evidence
R2 and R4: fully, cleanly, independently reproduced end-to-end in this session with zero manual intervention, real tool-native error/success text at every fault boundary (Traefik's own health-check behavior, PgBouncer's own `max_client_conn` error, Toxiproxy's own timeout behavior). R5's cAdvisor bug investigation: a genuinely excellent, honest, already-root-caused piece of documentation that this audit independently re-confirmed rather than merely trusted.

## Weakest Evidence
R1's current, as-committed reproducibility: the lab's central IAM ALLOW/DENY experiment fails on a fresh run of this checkout due to a real, confirmed, currently-present line-ending defect, and the failure is compounded by a real bug in the lab's own visualization script, which mislabels the resulting `InvalidAccessKeyId` error as a policy DENY rather than recognizing it as a different failure class entirely.

## Critical Gaps
1. R1: CRLF corruption in 3 container-executed scripts blocks the lab's core experiment out of the box.
2. R1: `visualize.sh` does not distinguish "credential doesn't exist" from "policy denies this action" — both render as DENY.
3. R3: `build-push.sh` mutates committed source (`app/server.py`) in place via `sed`, a reproducibility/hygiene wrinkle, not a correctness defect.
4. Several experiments across R1/R4/R5 were not re-executed in this session and should not be assumed to still pass — they are HISTORICALLY DOCUMENTED, not CURRENTLY VERIFIED.

## Recommended Fixes
1. Strip CRLF from R1's `provision.sh`, `break-iam.sh`, `fix-iam.sh` (the exact fix already proven and applied elsewhere in this project, e.g. R14's Patroni `entrypoint.sh`).
2. Fix `visualize.sh`'s DENY-classification logic to check for the specific error class, not just "the S3 call failed."
3. Have `build-push.sh` write its version via a build-arg/generated file rather than editing tracked source in place.
4. Re-run and re-capture evidence for the currently-HISTORICAL-ONLY experiments listed in `GAPS-AND-RECOMMENDATIONS.md` to convert them to freshly-verified status.

## Do NOT Rebuild
Every underlying mechanism in R1–R5 — the real AWS ECS credential-vending image, real MinIO IAM enforcement, real Traefik health-check load balancing, real Docker restart policies and cgroup limits, real Toxiproxy + PgBouncer network/pool fault injection, real Prometheus/Grafana/cAdvisor/stress-ng observability stack — is a correct, justified, already-reuse-audited architectural choice. Every identified gap in this audit is a line-ending/script-hygiene defect or an unverified-this-session status, never a wrong tool or a theory-only mechanism.

## Final Answer

**Does R1–R5 represent a genuine hands-on learning foundation?**

**Yes, substantially — with one currently-broken phase that must be understood honestly, not glossed over.** Four of five phases (R2, R3, R4, and R1's underlying mechanism once patched) demonstrate real, non-trivial, independently-reproducible failure injection and recovery, verified live in this session with genuine tool-native evidence, not documentation claims. R1, as currently committed to this repository, cannot self-provision its core IAM experiment due to a real, confirmed, currently-present line-ending defect — a real regression that documentation alone would never have revealed, and exactly the kind of gap this forensic audit was designed to surface. The project's own historical evidence logs were found, upon independent re-testing, to be genuine and non-fabricated wherever they were re-checked — this is a codebase whose documentation, on the whole, tells the truth about what it has actually done, with one currently-unpatched regression in R1 as the clearest exception.
