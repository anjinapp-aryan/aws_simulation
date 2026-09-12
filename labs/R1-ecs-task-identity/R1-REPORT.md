# Lab R1 Status

## GitHub reuse audit
| Repository | Purpose | License | Provides | Decision |
|---|---|---|---|---|
| `awslabs/amazon-ecs-local-container-endpoints` | Real ECS Task Metadata + Container Credentials protocol | Apache-2.0 | Real credential vending, real metadata endpoint | **REUSE unmodified** |
| `minio/minio` + `minio/mc` | Real S3-compatible API + real policy engine | AGPL-3.0 (self-hosted use, not distributed) | Real SigV4 auth, real ALLOW/DENY policy enforcement | **REUSE unmodified** |
| `getmoto/moto`, LocalStack Community, Ministack | API-shape AWS mocks | various | Same fidelity ceiling already proven insufficient (Phase 0 audit: fakes ECS/ALB/RDS) | **REJECTED** — would repeat the exact mistake this project already corrected for |
| Visualization tools (searched: IAM/policy graphers, container/network flow visualizers) | — | — | Closest hit: a 2-star static IAM policy grapher — wrong shape (graphs policy structure, not live per-request flow) | **None suitable — built smallest possible layer** (~90-line ANSI terminal diagram, zero new dependency, zero framework) |

## Components reused
`amazon-ecs-local-container-endpoints` (unmodified image), `minio/minio`, `minio/mc` (unmodified images).

## Components adapted
None at the code level — only configuration (credentials file content, `STS_ENDPOINT` experiment reverted — see below).

## Components newly built
`docker-compose.yml`, `scripts/provision.sh`, `scripts/break-iam.sh`, `scripts/fix-iam.sh`, `scripts/run-scenario.sh`, `scripts/visualize.sh`. All thin glue; no AWS logic reimplemented.

## Visualization solution
Built, not reused — audited first, nothing fit. Terminal ANSI flow diagram (Container → Metadata Endpoint → Task Credentials → IAM Evaluation → ALLOW/DENY → API result), colorized green/red, regenerated after every real API call from the real result.

## Exact runtime flow (as actually observed, not predicted)
```
app container
  → curl http://169.254.170.2/creds          [real HTTP call to the AWS-official tool]
  → real JSON: {AccessKeyId, SecretAccessKey, Token, Expiration}
  → aws s3 <op> --endpoint-url http://minio:9000, signed with those real credentials
  → MinIO validates the SigV4 signature (real) and evaluates the attached policy (real)
  → real 200 OK or real 403 AccessDenied
```

## Baseline result (evidence/01-baseline.log)
`s3:ListBucket` → **real ALLOW** (bucket listing returned). `s3:PutObject` → **real ALLOW** (upload confirmed). `s3:DeleteObject` → **real DENY** (`AccessDenied` — never granted, proving the baseline policy isn't over-broad).

## Failure result (evidence/02-break-observed.log)
After `break-iam.sh` replaced the attached policy with one missing `s3:PutObject`: `ListBucket` still ALLOW, **`PutObject` now real `AccessDenied`** — the identical call that succeeded in baseline, same credentials, only the policy changed. `DeleteObject` still DENY.

## Diagnosis
The evidence log and visual flow show the IAM Evaluation step routing to DENY specifically on `s3:PutObject`, with MinIO's real error text (`An error occurred (AccessDenied) when calling the PutObject operation`). Diagnosis path: compare against baseline → identify the one action whose result flipped → inspect the currently-attached policy (`config/policies/broken-missing-putobject.json` — visibly missing the `PutObject` statement present in `minimum-required.json`).

## Fix
`fix-iam.sh` reattaches `minimum-required.json` — List + Get + Put only. No wildcard action, no wildcard resource, no admin policy.

## Verification (evidence/03-fix-verify.log)
`PutObject` → **real ALLOW again**. `DeleteObject` → **still real DENY** — proving the fix restored exactly the missing permission and nothing more.

## Zero-cost confirmation
No AWS account touched. No AWS resource created. `docker compose down` removes everything. Total spend: $0.

## What is genuinely simulated (real behavior, not mocked)
Credential vending via the real ECS metadata/credentials protocol. Real request signing. Real policy-based authorization decisions (ALLOW/DENY) with real, distinguishable error text. A real observable state change (break → fix) with no restart required — MinIO re-evaluates the policy live on each request, exactly as real AWS IAM does.

## What still requires real AWS
Real STS temporary/rotating credentials (this lab uses a static long-lived key relayed through the real vending protocol — the protocol is real, the rotation is not). Real AWS IAM's exact policy-evaluation semantics (explicit deny precedence, permission boundaries, SCPs — MinIO's engine is policy-shaped but not IAM-identical). Real ECS task scheduling, real CloudWatch integration. These remain correctly deferred to CHEAP_MODE real-AWS labs per the Phase-Audit roadmap.

## Known limitations
1. **Session token not forwarded to MinIO** — documented above and in `scripts/run-scenario.sh`. MinIO's single-node default config doesn't validate AWS-style session tokens for admin-created users; the scenario script uses the real vended AccessKeyId/SecretAccessKey directly. This was discovered by testing (not assumed): `GetSessionToken` against MinIO's STS returned a genuine `Unsupported action GetSessionToken` error, and MinIO's `AssumeRole` endpoint returned `unsupported API call` in this deployment mode — both real, both investigated, both correctly worked around rather than faked.
2. **Windows/Git Bash path mangling** — `MSYS_NO_PATHCONV=1` is required before any `docker compose run --entrypoint /bin/sh ...` command, or Git Bash rewrites the Unix path into a broken Windows one. Documented in the README's exact commands.
3. Root MinIO admin credentials are static values in `docker-compose.yml`, appropriate for a $0 local lab, not for anything internet-exposed.

## Recommended next lab
**R2 — ALB-shaped failure** (nginx/Traefik in front of two containers: kill a backend → real 502/503, break the health-check path → real unhealthy state, fix → real recovery), per `phase-audit/RECOMMENDED-ROADMAP.md`. After R1+R2, the smallest real-AWS lab (R3 — deploy only `modules/network` + `modules/security_groups`) becomes the natural next step for anything R1/R2 cannot reproduce locally.
