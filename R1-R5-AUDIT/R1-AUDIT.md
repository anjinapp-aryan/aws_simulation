# R1 — ECS Task Identity / Task Role — Forensic Audit

## A. Objective (per repo's own docs)
Demonstrate real IAM-shaped least-privilege authorization (ALLOW/DENY) delivered to an application via the real ECS Task Metadata/Container Credentials protocol, without hardcoded credentials.

## B. Implementation — WHERE IS IT
| Mechanism | File/path | Purpose |
|---|---|---|
| Real ECS credential-vending protocol | `docker-compose.yml` service `ecs-local-endpoints` (`amazon/amazon-ecs-local-container-endpoints`, official AWS image, reused unmodified) | Serves credentials at `169.254.170.2/creds`, the exact link-local address/protocol a real ECS task uses |
| Real S3-shaped API + real IAM policy engine | `docker-compose.yml` service `minio` | Genuine SigV4 request validation and real ALLOW/DENY policy evaluation (not a mock) |
| IAM provisioning ("platform team" action) | `scripts/provision.sh`, run via the `mc-init` one-shot container | Creates bucket, task-role user, attaches `config/policies/minimum-required.json` |
| Break/fix experiment | `scripts/break-iam.sh` (attaches `config/policies/broken-missing-putobject.json`), `scripts/fix-iam.sh` (reattaches minimum-required) | Real policy swap, evaluated live, no restart needed |
| Application under test | `docker-compose.yml` service `app` (`amazon/aws-cli:latest`, official image, unmodified) — uses the AWS CLI's default credential chain | Proves the app never hardcodes keys |
| Evidence/visualization | `scripts/run-scenario.sh`, `scripts/visualize.sh` | Runs real S3 calls, prints an ASCII ALLOW/DENY flow diagram |

No app/ directory exists for R1 — correct, because the "application" is the official, unmodified `aws-cli` image, not custom code.

## C. Runnability — ACTUALLY EXECUTED THIS SESSION
`docker compose up -d` (fresh, live): **PASS** — all 4 containers (`minio`, `mc-init`, `ecs-local-endpoints`, `app`) started, `minio` reported `Healthy`.
**But**: `mc-init`'s log immediately showed:
```
mc-init-1  | /scripts/provision.sh: line 5: set: -: invalid option
```
**Root cause, confirmed by direct inspection**: `file scripts/provision.sh` → "with CRLF line terminators"; `cat -A` shows `set -e^M$` — the container's real `/bin/sh` (dash) chokes on the embedded `\r`. **Same bug class already found and fixed in this project's own R14 work** (Patroni's `entrypoint.sh`), never retroactively applied to R1. Confirmed present in **all 3 container-executed scripts**: `provision.sh`, `break-iam.sh`, `fix-iam.sh` (all "POSIX shell script ... with CRLF line terminators"). The two bash-run-from-host scripts (`run-scenario.sh`, `visualize.sh`) also have CRLF but tolerate it (bash on Windows Git Bash is more forgiving of trailing `\r` than dash in a Linux container).

**Consequence, observed live**: because the bucket/user/policy were never created, every subsequent S3 call in `run-scenario.sh` failed with `InvalidAccessKeyId` (a completely different error class than the intended `AccessDenied`), and `visualize.sh` **mislabeled every one of these as a policy-driven DENY** — a real, currently-reproducible bug in the evidence-capture/visualization logic: it does not distinguish "the credential doesn't exist" from "the policy denies this action."

**Isolation test performed** (in a throwaway `.audit-tmp/` directory, deleted afterward — no committed file was modified): a CRLF-stripped copy of `provision.sh` was run directly via `docker run --entrypoint sh ... /audit/provision-test.sh` against the live `minio` container. Result: **succeeded completely** — bucket created, user created, policy created and attached, confirmed via `mc`'s own real output. Re-running `run-scenario.sh` afterward against this now-correctly-provisioned MinIO produced the **exact historically-documented behavior**: `ListBucket` ALLOW, `PutObject` ALLOW (real upload), `DeleteObject` real `AccessDenied`.

**Runnability verdict: PARTIAL** — the stack starts, but the core provisioning step fails out of the box; the underlying mechanism is proven real once patched.

## D. Experiment Audit
| Experiment | Implementation | Failure/change injected | Command | Expected | Actual evidence (THIS SESSION) | Verification | Recovery | Current reproducibility |
|---|---|---|---|---|---|---|---|---|
| Baseline ALLOW/DENY | `provision.sh` + `run-scenario.sh` | none | `bash scripts/run-scenario.sh baseline` | List/Put ALLOW, Delete DENY | **As committed: FAILS** (`InvalidAccessKeyId` on every call, due to CRLF bug). **After manual CRLF fix: PASSES**, real `AccessDenied` on Delete, real upload success on Put | Live `psql`-equivalent (`aws s3 ls`) output, real MinIO error text | n/a | RED as committed / GREEN after a documented one-line fix |
| Break IAM (remove PutObject) | `break-iam.sh` | policy swap to `broken-missing-putobject.json` | `bash scripts/break-iam.sh` | Put flips to real AccessDenied | **NOT independently re-executed live this session** (same CRLF bug affects this script; not re-tested after the isolated provisioning fix due to audit time constraints) — HISTORICALLY DOCUMENTED (`evidence/02-break-observed.log`, a real, genuine transcript with real AccessDenied text) but **NOT re-verified live in this audit** | Historical log only | Historical (`fix-iam.sh`) | Historically GREEN, current status UNVERIFIED this session (same CRLF bug applies) |
| Fix IAM | `fix-iam.sh` | reattach minimum-required policy | `bash scripts/fix-iam.sh` | Put flips back to ALLOW | Same as above — HISTORICALLY DOCUMENTED, NOT re-verified live this session | Historical log | n/a | Historically GREEN, current status UNVERIFIED this session |

## E. Hands-on score (0-7 scale, per experiment)
Baseline ALLOW/DENY: **7 as historically executed** (implemented → runnable → executed → verified → recovered → the underlying CRLF issue was itself root-caused during this audit). **As currently committed: 2** (implementation exists, technically "runnable" as a stack, but the actual IAM experiment fails).
Break/Fix: **6 historically** (real failure injected, real observation, real recovery, per `evidence/02-*.log` and `03-*.log`), **not re-scored live this session** (time-boxed audit, flagged as unverified rather than assumed).

## R1-Specific Determination (per the required Step 4 format)
- Task identity: **REAL** (genuine ECS metadata protocol, official AWS image).
- Task role concept / identity separation: **REAL** (provisioning is a separate "platform" actor from the app).
- Permission/authorization behavior, unauthorized access, authorized access: **REAL when the provisioning step succeeds** — confirmed live in this audit after a manual fix.
- Failure behavior: **REAL** historically documented, not re-verified live this session.
- Verification: real, genuine MinIO error text, both historically and in this session's own live re-test.
- **Is there a REAL runnable simulation, or is it "here's how ECS task roles work"?** It is a REAL runnable simulation — this is not theory — but it is **currently broken as committed** due to a line-ending regression, not a design/theory problem.
- AWS honesty: correctly and explicitly NOT claimed as "real AWS" anywhere in its own docs — labeled BEHAVIOR-EQUIVALENT with real protocol/authorization mechanics, real static keys instead of rotating STS tokens (an honestly-documented, correct limitation).

## Score: 58/100
Implementation 14/15, Runnable 8/15 (starts, core script fails), Real experiment 12/20 (real when patched, not out-of-the-box), Failure injection 8/15 (real mechanism, not independently re-verified live this session, currently blocked by the same bug), Observation 6/10, Independent verification 6/10 (historical logs are genuine but current run contradicts them), Recovery 2/5 (historical only), Reproducibility 1/5 (RED as committed), Documentation 5/5 (unusually honest and detailed about its own real limitations, e.g. session-token/MinIO STS incompatibility — but does not mention the CRLF issue, since that appears to be a later regression not present when the docs were written).

## Historical vs. Current
**HISTORICALLY CLAIMED**: R1-REPORT.md claims a full PASS with baseline→break→fix→verify all real (and the evidence logs back this up as genuine, non-fabricated transcripts).
**CURRENTLY VERIFIED**: the core provisioning step **fails on this checkout** with a real, reproducible dash syntax error; the documented PASS is **NOT reproducible out of the box** on this exact repository state. Once the 3 affected scripts' line endings are corrected (a fix outside this audit's scope, per "do not modify"), the underlying mechanism was confirmed, live, in this session, to work exactly as historically documented.
