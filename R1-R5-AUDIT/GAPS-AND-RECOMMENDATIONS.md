# R1–R5 Gaps and Recommendations

Only evidence-backed gaps are listed — nothing here was invented to pad the report.

## BROKEN
- **R1**: `scripts/provision.sh`, `scripts/break-iam.sh`, `scripts/fix-iam.sh` — CRLF line-ending corruption causes a real dash syntax error inside the container's `/bin/sh`, blocking the lab's core IAM provisioning step on a fresh run of this exact checkout. Confirmed live, this session, with the exact error text captured.

## PARTIAL / TIMING-SENSITIVE
- **R3 OOM experiment**: the `OOMKilled` inspect flag resets to `false` near-instantly once `restart: on-failure` relaunches the container, making it genuinely hard to catch in a single quick check (confirmed both by this session's own re-test and by the project's own pre-existing evidence log, which independently arrived at the same "requires multiple cycles" finding). Not a defect — a real Docker behavior worth noting for anyone extending this lab.

## UNVERIFIED (this session)
- R1's break/fix cycle (blocked by the CRLF bug, not independently re-attempted after the isolated fix).
- R4's network-cut / bad-credentials experiments.
- R5's memory-pressure, cascading-failure, and DB-latency-under-load experiments.
None of these are known to be broken — they simply were not re-executed in this audit's time-boxed session. They should not be reported as either PASS or FAIL until re-tested.

## OUTDATED / FRAGILE (code quality, not correctness)
- **R3's `build-push.sh`**: uses `sed -i` to bake a version string directly into the committed `app/server.py`, then deletes its own backup file — real and functional, but mutates tracked source as a side effect of normal use, and is not idempotent across repeated tag builds.

## EXCELLENT (worth explicitly protecting, not rebuilding)
- **R2 and R4** are clean, currently reproducible, zero-manual-intervention, real hands-on labs — do not touch.
- **R5's own pre-existing bug-investigation logs** (`cadvisor-bug-investigation.log`, `bug-no-oom-first-attempt.log`) are genuinely excellent, honest, root-caused documentation — exactly the standard this whole project claims to hold itself to, and in these two specific cases, actually does. This audit independently re-confirmed the cAdvisor finding is still accurate today.
- **R3's kill-vs-crash distinction** (`docker kill` does not trigger `restart: on-failure`; a self-exiting process does) is a genuine, correctly-documented, non-obvious Docker behavior finding — keep it exactly as written.

## Recommended fixes (in priority order)
1. Strip CRLF from R1's 3 container-executed scripts (`sed -i 's/\r$//'` or equivalent) — a one-line-per-file fix, same remediation already proven and applied elsewhere in this project's later phases (R14).
2. Fix `visualize.sh`'s error classification so it distinguishes a credential-not-found error (`InvalidAccessKeyId`) from a real policy DENY (`AccessDenied`) rather than labeling both as DENY — discovered live during this audit when the CRLF bug's downstream effect exposed the gap.
3. Consider making `build-push.sh` write the version into a build-arg or generated file instead of mutating the committed `server.py` in place, to remove the reproducibility/idempotency wrinkle noted above.
4. Re-run and re-capture evidence for R1's break/fix cycle, R4's network-cut/bad-credentials, and R5's memory-pressure/cascading-failure/DB-latency experiments to convert their current HISTORICAL-ONLY status to freshly-verified — none of these are expected to fail based on any evidence gathered in this audit, but none should be marked verified until they are re-run.

## What should NOT be rebuilt
Every underlying mechanism across R1–R5 (real ECS credential-vending + real MinIO IAM; real Traefik health-check-driven LB; real Docker restart policies and cgroup limits; real Toxiproxy + PgBouncer; real Prometheus/Grafana/cAdvisor/stress-ng) is a correct, justified, already-reuse-audited choice. The identified gaps are line-endings and script hygiene, not architecture or tool selection.
