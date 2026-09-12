# Phase 3 Report — IAM + Security Groups

## Executive Summary
Phase 3 studied Blueprint's IAM and Security Group implementation, audited 7 external candidates, and ran every test in the repository. **Zero AWS resources created, zero AWS API calls, $0.00 spend.**

The phase produced one finding that overturns conclusions from two earlier phases, and one finding that survives verification and defines the (very small) remaining work.

---

## ⚠️ Finding 1 — I was wrong in Phase 1 and Phase 2. The repo is not broken.

**Previously reported**: Phase 1 "found a real bug" in `modules/network`'s test; Phase 2 "proved" the root cause was HCL language behaviour, explicitly classified as *"not repo-specific, not environment-specific."*

**Actually true**: my Terraform version was wrong.

| Terraform | `null != null && trimspace(null) != ""` |
|---|---|
| **1.9.8** (mine) | ERROR |
| **1.13.1** (repo's pinned CI version) | `false` — short-circuits correctly |

Full test suite on the correct version: **77 passed, 0 failed, across all 17 modules.** On 1.9.8: 12 of 17 suites fail. Evidence for the pin: `.github/actions/setup-terraform/action.yml` → `terraform-version: "1.13.1"`.

**The genuine residual finding** (much narrower, still real): `required_version = ">= 1.8.0, < 2.0.0"` is **too permissive**. The code requires `&&` short-circuit evaluation, absent in 1.8–1.9.x — versions the constraint explicitly permits. Anyone on those versions hits confusing failures across 12 modules.

**Methodology lesson**: I praised `least_privilege.tftest.hcl` as proof of rigour in two phases **without executing it**, then nearly declared the repo systemically broken when it failed on the wrong toolchain. Both errors share one cause — drawing conclusions without running the project's own pinned tooling.

## Finding 2 — The IAM testing gap is real, and it's a choice, not a limitation

**Confirmed by static analysis** (version-independent): across 17 test files there is exactly **one** IAM assertion — `length(aws_iam_role.enhanced_monitoring) == 1`, an existence check. **Nothing** asserts trust principals, action scope, resource scope, conditions, or the task/execution role boundary. Meanwhile SGs get 5 exact-count least-privilege assertions, all passing.

**But my proposed mechanism was wrong.** I claimed Terraform's mocking *structurally prevents* IAM assertions. Disproved by experiment: a test that simply doesn't mock `aws_iam_policy_document`, with a `skip_credentials_validation` provider block, asserts real rendered policy JSON successfully — **2 passed, 0 failed, zero credentials, zero API calls**. `aws_iam_policy_document` is rendered locally by the provider, not fetched from AWS.

So the gap is a **design choice** in Blueprint's tests (likely collateral from mocking the provider wholesale to satisfy `aws_caller_identity`/`aws_region`), which makes it cheap to close.

---

## Reuse decisions

| Decision | Item | Rationale |
|---|---|---|
| **REUSE unchanged** | Blueprint's IAM (`modules/ecs_service/iam.tf`) + SG (`modules/security_groups/`) | 77/77 tests pass; SG least privilege already asserted better than most projects manage |
| **ADAPT** (deferred to Ph5/6) | workshop labs 2 & 4 | real working scripts for exactly our scenarios; only discovery filters need rewriting for Blueprint naming |
| **REFERENCE** | `awslabs/terraform-iam-policy-validator` | AWS-official, MIT-0, semantically strong — but **requires AWS credentials** and **charges per custom policy check**; incompatible with a zero-cost phase. Revisit at Phase 5+ |
| **REFERENCE** | `terraform-aws-modules/terraform-aws-iam` | hides the task/execution split we must learn |
| **REFERENCE ONLY, don't deploy** | `BishopFox/iam-vulnerable` | excellent for policy evaluation/escalation, but creates real exploitable IAM |
| **DO NOT USE** | `terraform-aws-modules/terraform-aws-security-group` | no gap to fill + license is NOASSERTION (unverified) |
| **DO NOT USE** | `cloudgoat` | 3,726 stars and still wrong-fit — off-scope, insecure-by-design |
| **BUILD — DONE** | `modules/ecs_service/tests/iam_role_boundary.tftest.hcl` | written, run, and negative-tested this phase — see below |

## What was NOT built
No IAM module. No SG module. No policy-analysis engine. No generic security framework. No second architecture. Exactly one file was added to the vendored Blueprint clone: the IAM boundary test.

## The IAM boundary test — built and verified this phase

**File**: `candidates/AWS-ECS-Blueprint/modules/ecs_service/tests/iam_role_boundary.tftest.hcl` (5 runs)

**Mechanism**: real (unmocked) `aws_iam_policy_document`, credential-free provider block (`skip_credentials_validation`/`skip_requesting_account_id`/`skip_metadata_api_check`) — the pattern proven feasible earlier in Phase 3. `command = plan`, zero AWS API calls.

**Assertions**:
1. Execution role carries `AmazonECSTaskExecutionRolePolicy` + a secrets policy granting `secretsmanager:GetSecretValue` and `kms:Decrypt`
2. Execution role's secrets policy is scoped to the supplied secret ARN, not `"*"`
3. Task role carries the caller-supplied application permission (`s3:GetObject`)
4. **Boundary**: task role does not grant `secretsmanager:`, `ssm:GetParameter`, `ecr:`, or `logs:CreateLogStream`
5. Both roles trust only `ecs-tasks.amazonaws.com`; task role and execution role are distinct roles

**Two real bugs found and fixed while building it** (both are test-authoring corrections, not Blueprint defects):
- My first draft's secret ARN didn't match the `valueFrom` full-form ECS expects; `locals.secret_policy_resources` correctly truncates it to the base ARN — my assertion was wrong, not the module.
- My first draft compared `task_role_arn != execution_role_arn`, both unknown at `plan` time (Terraform rejected it: "Unknown condition value"). Fixed by comparing the role **names** instead, which are known from input variables.

**Negative test — proof the assertion actually detects a violation**: temporarily added a 6th run injecting `secretsmanager:GetSecretValue` into the task role's policy. Result: **`fail`**, with the exact intended message — `"BOUNDARY VIOLATION: task role must not grant Secrets Manager access; startup secrets belong to the execution role."` Reverted immediately; confirmed zero trace remains (`grep -c NEGATIVE` → 0) and the suite returns to a clean pass.

**Full Blueprint suite after the addition**: **82 passed, 0 failed**, across all 17 modules, on Terraform 1.13.1 (77 baseline − 4 old `ecs_service` tests folded into the same run + 9 new `ecs_service` total = 82). Zero AWS credentials, zero AWS API calls, zero AWS resources.

**One additional reuse-audit item closed this phase**: checked whether the AWS provider exposes an IAM Policy Simulator data source (`aws_iam_principal_policy_simulation` or similar) that could replace the `strcontains()` approach. Confirmed via the provider's published schema (v6.64.0): **no such data source exists.** IAM Policy Simulator is a standalone AWS API requiring a real, already-created principal — it could never run credential-free at plan time even if wrapped. This closes Candidate C from the reuse audit and confirms the built test is the correct zero-cost mechanism, not a fallback from a better option.

---

## Zero-cost validation performed
```
terraform fmt -check -recursive   → clean, 0 diffs
terraform validate                → pass (both TF versions)
terraform test                    → all 17 modules × 2 TF versions
terraform console                 → short-circuit experiments
scratchpad IAM assertion experiment → 2 passed, 0 failed
```
No `plan`, `apply`, or `destroy`. No credentials configured.

## Deferred to later phases (roadmap not reordered)
| Scenario | Needs | Phase |
|---|---|---|
| Execution role → ECR / CloudWatch / Secrets failures | running ECS | **5** |
| Task role → runtime `AccessDenied` | running ECS | **5** |
| ECS → RDS SG rule removal | ECS + RDS | **6** |
| Over-permissive SG comparison | nothing | **done now** (Terraform-level, in `failure-scenarios.md`) |

---

## PHASE 3 STATUS: **PASS**

**REUSE**: Blueprint IAM + SG implementation, unchanged.

**ADAPT**: workshop labs 2 & 4 (discovery filters → Blueprint naming) — at Phases 5/6.

**REFERENCE**: `terraform-iam-policy-validator` (revisit Phase 5+ when AWS is live and the per-check charge is justifiable); `terraform-aws-modules/terraform-aws-iam`; `iam-vulnerable` (read-only).

**BUILD — DONE**: `modules/ecs_service/tests/iam_role_boundary.tftest.hcl`, 5 runs, asserting (a) execution role holds ECR/CloudWatch/Secrets startup permissions, (b) task role holds application permissions, (c) task role excludes execution-role-only permissions, (d) both roles trust only `ecs-tasks.amazonaws.com`. Negative-tested (violation correctly caught, then reverted clean). Full suite: 82/0 failed.

**AWS DEFERRED**: all four failure injections → Phases 5 and 6. No AWS resources created this phase.

**KEY LEARNING**:
1. Execution role = AWS starting your container; task role = your code doing its job. Startup failure vs runtime failure is the diagnostic tell.
2. Least privilege is proven by **counting what is absent** (`== 1`, not `>= 1`).
3. SG-to-SG references grant access to an *identity*; CIDR rules grant access to an *address* — and to whatever occupies it later.
4. `AccessDenied` = IAM; timeout = network. Never conflate.
5. **Run the project's pinned toolchain before concluding anything about it.**

**NEXT PHASE**: Phase 4 — ALB. No unresolved IAM/SG confusion blocks it. Two open items carried forward: (a) the `required_version` constraint bug is unreported upstream and unfixed by us (deliberately — we don't modify the vendored repo), (b) the IAM boundary test is designed but unbuilt.
