# Phase 3 GitHub Reuse Audit — IAM + Security Groups

## Objective
Identify existing, mature implementations for Phase 3 (IAM + Security Groups) so we build the minimum custom code while maximising real learning. Decide REUSE / ADAPT / REFERENCE / DO NOT USE / BUILD **before** writing anything.

## Search Strategy
1. Inventory what the existing foundation (`AWS-ECS-Blueprint`) already provides — establish the baseline first, so "gaps" are evidence-based rather than assumed.
2. Re-check already-cloned repos for Phase 3-relevant material before searching for new ones (cheapest possible reuse).
3. GitHub API search + targeted repo health checks for: IAM modules, SG modules, IAM policy testing/validation, vulnerable-by-design IAM labs.
4. Evaluate each against learning value, not popularity.

---

## Baseline: what AWS-ECS-Blueprint already has (verified this phase)

```
IAM:  14 × aws_iam_role
      11 × aws_iam_role_policy (inline)
       8 × aws_iam_role_policy_attachment (managed)
       2 × aws_iam_policy (customer-managed)

SG:    9 × aws_security_group
       6 × aws_security_group_rule
       1 × aws_default_security_group   (lockdown)

Tests: 17 × .tftest.hcl
```

### ⚠️ The single most important finding of this audit
**Security Groups are rigorously tested for least privilege. IAM is not tested at all.**

Evidence:
- `modules/security_groups/tests/least_privilege.tftest.hcl` — 5 runs with exact assertions (e.g. *exactly one* TCP/3306 ingress rule, app-port propagation, RDS port isolation).
- Across all 17 test files, there is exactly **one** IAM-related assertion: `modules/rds/tests/production_defaults.tftest.hcl` → `length(aws_iam_role.enhanced_monitoring) == 1`. That is an **existence/count check, not a permissions check**.
- **Zero** assertions anywhere about trust policies, permission scope, least privilege, or the task-role/execution-role split.
- Worse: **7 test files mock `aws_iam_policy_document` with an empty statement list**:
  ```hcl
  mock_provider "aws" {
    mock_data "aws_iam_policy_document" {
      defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
    }
  }
  ```
  Because the data source is mocked to return *no statements*, the module's real policy logic (`data.aws_iam_policy_document.execution_secrets` and its conditional statements) is **evaluated away before any assertion could inspect it**. The mocking approach structurally *prevents* IAM policy content from being testable through `terraform test`.

This is the genuine, evidence-backed Phase 3 gap — and it defines what (little) we should build.

---

## Candidate Repositories

### Candidate A — `sample-devops-agent-ecs-workshop` (already cloned, Phase 0)
- **URL**: github.com/aws-samples/sample-devops-agent-ecs-workshop
- **Purpose**: 10 ECS troubleshooting labs with `inject.sh`/`fix.sh` pairs
- **License**: MIT-0 ✅ | **Maintenance**: active (918 commits, last push 2026-01-15)
- **Phase 3 relevance — verified by reading the scripts this phase**:
  - `lab2-secrets-access-denied/inject.sh` — discovers the ECS **execution role**, finds its secrets policy, detaches it → produces a real IAM `AccessDenied` at task startup. **This is exactly §19's first scenario.**
  - `lab4-security-group-blocked/inject.sh` — discovers the RDS SG and the task SG by tag, removes the ingress rule → ECS cannot reach RDS. **This is exactly §19's third scenario.**
- **Strengths**: real working AWS CLI scripts, not stubs; `fix.sh` serves as the answer key (to be withheld until after diagnosis, per §14).
- **Weaknesses**: discovery filters are hardcoded to the workshop's own naming (`retail-store-ecs-cluster`, `Values=*catalog*db*`, `tag:ecsdevopsagent`). Will **not** find Blueprint resources unmodified.
- **Learning value**: **Highest of any candidate** — it teaches the exact failure modes Phase 3 targets.
- **Decision: ADAPT** (rewrite discovery filters for Blueprint naming; keep the injection/restore logic and the backup-to-`/tmp` safety pattern).

### Candidate B — `awslabs/terraform-iam-policy-validator`
- **URL**: github.com/awslabs/terraform-iam-policy-validator
- **Purpose**: validates IAM policies in a Terraform **plan** against IAM Access Analyzer — checks for findings, policy validity, and custom "no broader than" checks.
- **License**: MIT-0 ✅ | **Stars**: 355 | **Maintenance**: ⚠️ AWS Labs official, but last push **2025-06-09** (~15 months before this audit)
- **Strengths**: operates on the **real rendered plan JSON**, so it sidesteps exactly the empty-mock problem that makes IAM untestable via `terraform test`. Directly fills the identified gap. AWS-official tooling.
- **Weaknesses**: staleness; requires a `terraform plan` (so AWS credentials, though plan creates nothing); Python tool, adds a toolchain dependency.
- **Learning value**: High — teaches IAM policy validation as a CI gate, the natural counterpart to the SG least-privilege test.
- **Decision: REFERENCE now → candidate ADAPT in the hands-on stage.** Verify the staleness is benign against current Terraform/provider versions before committing to it.

### Candidate C — `terraform-aws-modules/terraform-aws-iam`
- **License**: Apache-2.0 ✅ | **Stars**: 869 | **Maintenance**: excellent (last push 2026-08-28, 2 open issues)
- **Strengths**: comprehensive, well-maintained submodules for every IAM pattern.
- **Weaknesses for *this* project: it abstracts away exactly what Phase 3 must teach.** Blueprint's `modules/ecs_service/iam.tf` is ~90 readable lines where you can see the trust policy, the assume-role principal, the conditional secrets policy and the task/execution split directly. This module would replace that with variable inputs and hide the mechanism.
- **Decision: REFERENCE** (compare API design; do **not** replace Blueprint's IAM).
- **Reason**: same principle that settled Phase 2 — a 4,064-line VPC module was rejected for hiding the CIDR math. Consistency: consumption artifacts ≠ learning artifacts.

### Candidate D — `terraform-aws-modules/terraform-aws-security-group`
- **License**: ⚠️ **NOASSERTION** (GitHub could not classify it — must read the LICENSE file directly before any reuse; the sibling modules are Apache-2.0, so this is likely a detection artifact, but *unverified*)
- **Stars**: 594 | **Maintenance**: active (last push 2026-08-06)
- **Weaknesses**: Blueprint's SG implementation is already tested more rigorously than most projects achieve (`least_privilege.tftest.hcl`). Replacing a *tested* implementation with an *untested-by-us* one is a net regression for this project.
- **Decision: DO NOT USE** — no gap to fill, and an unresolved license question makes it the weakest candidate on a dimension that actually matters.

### Candidate E — `BishopFox/iam-vulnerable`
- **License**: MIT ✅ | **Stars**: 590 | **Maintenance**: reasonable (last push 2026-03-12)
- **Purpose**: Terraform-deployed, vulnerable-by-design IAM privilege-escalation playground (~31 escalation paths).
- **Strengths**: genuinely excellent for learning IAM **policy evaluation, explicit deny, and privilege escalation** — concepts Blueprint cannot teach because it (correctly) has no vulnerabilities.
- **Weaknesses**: ⚠️ **deliberately creates insecure IAM in a real AWS account.** Wholly separate architecture from Blueprint. Creates real, exploitable roles — a genuine security consideration for a personal AWS account, and it must be destroyed promptly.
- **Decision: REFERENCE ONLY** — read its policies to understand escalation paths; **do not deploy** into the same account/project as the Blueprint work. If ever deployed, it belongs in an isolated throwaway account, which is out of scope here.

### Candidate F — `RhinoSecurityLabs/cloudgoat`
- **License**: BSD-3-Clause ✅ | **Stars**: 3,726 | **Maintenance**: active (last push 2026-04-28, 24 open issues)
- **Purpose**: "vulnerable by design" AWS scenario deployer (Terraform-based), broader than IAM.
- **Weaknesses**: same insecure-by-design concern as E, plus much broader scope (EC2/S3/Lambda attack paths) than Phase 3 needs. Highest star count of any candidate and still not the right fit — a good illustration of why stars aren't the criterion.
- **Decision: DO NOT USE** (for Phase 3; possibly revisit at Phase 12/13 for adversarial scenarios).

---

## Comparison Matrix

| Repo | IAM | SG | ECS | Tests | Maintenance | License | Learning value | Decision |
|---|---|---|---|---|---|---|---|---|
| **AWS-ECS-Blueprint** (baseline) | ✅ 14 roles | ✅ 9 SGs + tested | ✅ | 🟡 SG tested, **IAM untested** | Active | MIT | Highest — readable | **PRIMARY (keep)** |
| **sample-devops-agent-ecs-workshop** | ✅ lab2 | ✅ lab4 | ✅ | n/a (scripts) | Active | MIT-0 | **Highest for failure injection** | **ADAPT** |
| awslabs/terraform-iam-policy-validator | ✅ validation | ❌ | ❌ | n/a (tool) | ⚠️ 15mo stale | MIT-0 | High — fills the real gap | **REFERENCE → maybe ADAPT** |
| terraform-aws-modules/terraform-aws-iam | ✅ | ❌ | 🟡 | ✅ | Excellent | Apache-2.0 | ⚠️ Hides the concept | **REFERENCE** |
| terraform-aws-modules/terraform-aws-security-group | ❌ | ✅ | ❌ | ✅ | Active | ⚠️ NOASSERTION | Low (no gap) | **DO NOT USE** |
| BishopFox/iam-vulnerable | ✅ escalation | ❌ | ❌ | ❌ | OK | MIT | High (policy evaluation) | **REFERENCE ONLY** |
| RhinoSecurityLabs/cloudgoat | 🟡 | 🟡 | 🟡 | ❌ | Active | BSD-3 | Off-scope for Phase 3 | **DO NOT USE** |

---

## Final Recommendation

- **PRIMARY FOUNDATION**: `AWS-ECS-Blueprint` — `modules/ecs_service/iam.tf` (task vs execution role), `modules/security_groups/` (+ its least-privilege test), `modules/network`'s `aws_security_group.interface_endpoints`, and the endpoint policies in `local.interface_endpoint_actions` (resource-policy vs identity-policy teaching material).
- **SECONDARY REFERENCE**: `sample-devops-agent-ecs-workshop` labs 2 & 4 (adapted), `awslabs/terraform-iam-policy-validator`.
- **REFERENCE ONLY**: `terraform-aws-modules/terraform-aws-iam`, `BishopFox/iam-vulnerable`.
- **DO NOT USE**: `terraform-aws-modules/terraform-aws-security-group` (no gap + license unverified), `cloudgoat` (off-scope, insecure-by-design).
- **CUSTOM BUILD**: one small thing only — see below.

### What we reuse
Blueprint's entire IAM + SG implementation, unchanged. The `least_privilege.tftest.hcl` pattern as the model for how security properties should be asserted.

### What we adapt
The two workshop lab scripts — rewriting only the **resource-discovery filters** (Blueprint naming/tags instead of `retail-store-ecs-cluster`/`ecsdevopsagent`), keeping their injection logic, `/tmp` backup pattern, and `fix.sh`-as-answer-key discipline.

### What we build
**One thing**: an IAM least-privilege assertion capability, because the audit proved none exists and the current mocking approach prevents one via `terraform test`. Two options, to be decided at implementation time:
1. Adapt `awslabs/terraform-iam-policy-validator` (AWS-official, plan-JSON based) — preferred if it still works on current Terraform/provider versions.
2. A minimal custom check over `terraform plan -json` output asserting the task-role/execution-role boundary (e.g. *the task role must not hold `ecr:*` or `secretsmanager:GetSecretValue`* — those belong to the execution role).

### What we explicitly do NOT build
A new IAM module. A new SG module. A new ECS security architecture. Any replacement for a Blueprint module that already works and, in the SG case, is already better-tested than the alternatives.

---

## Phase 3 Implementation Plan (not started — awaiting go-ahead)

**Stage 1 — Study (zero cost)**
Trace `modules/ecs_service/iam.tf` line by line: trust policy → `sts:AssumeRole` with `ecs-tasks.amazonaws.com` → execution role + `AmazonECSTaskExecutionRolePolicy` → conditional secrets policy (`count = length(var.secret_arns) > 0 || ...`) → task role → conditional KMS/inline policies. Then `modules/security_groups/` SG-to-SG references. Then the endpoint policies in `modules/network` as the identity-vs-resource-policy contrast.

**Stage 2 — Zero-cost validation**
`terraform fmt` / `validate` / `test` on `modules/security_groups` (its test has been read but **never executed** — an open item carried from Phase 1). Confirm whether the empty-`aws_iam_policy_document` mock is what blocks IAM assertions, or whether a targeted test could work around it.

**Stage 3 — Reuse decision on the IAM validator**
Clone `awslabs/terraform-iam-policy-validator`, verify compatibility with Terraform 1.9.8 / AWS provider 6.x, decide ADAPT vs minimal custom check.

**Stage 4 — Failure injection design (paper first)**
Adapt lab2 and lab4 discovery filters to Blueprint naming. Write the SYMPTOM → FIRST CHECK → EVIDENCE → HYPOTHESIS → ROOT CAUSE → FIX → VALIDATION runbook for each **before** running anything, so diagnosis isn't contaminated by knowing the injection.

**Stage 5 — Real AWS (only if authorised, CHEAP_MODE, separate cost review)**
The three §19 scenarios require running ECS — which is **Phase 5** territory. Phase 3's real-AWS component may therefore need to be deferred until ECS exists, or limited to IAM-only experiments (role assumption, `AccessDenied` reproduction) that don't need a running task. **Flagged now as a sequencing dependency**, to be resolved before any deployment.

---

## Sequencing risk worth raising now
Phase 3's most valuable exercises (execution-role → ECR failure; SG → RDS failure) **cannot be executed without ECS and RDS running**, which are Phases 5 and 6. Options: (a) keep Phase 3 as study + zero-cost validation and run its failure injections during Phase 5/6, or (b) reorder. Recommend **(a)** — it preserves the roadmap and keeps cost at zero, at the cost of splitting Phase 3's hands-on portion across later phases.

**Status: audit complete. No code written. No AWS resources created. No `terraform apply`. Awaiting your decision before implementation.**

---

## Addendum — Candidate C: `terraform test` + IAM Policy Simulator pattern

**Investigated**: whether Terraform exposes AWS's IAM Policy Simulator (`iam:SimulatePrincipalPolicy`) as a data source usable inside `.tftest.hcl`.

**Finding**: it does not exist. Checked the AWS provider's published schema (v6.64.0) for any data source matching `iam` + `simulat`/`policy` — zero matches. IAM Policy Simulator is a standalone AWS API, never wrapped by the `hashicorp/aws` provider. Even if it were, it requires the role to actually **exist in AWS** (it simulates against a real principal), so it could never run credential-free at plan time — it's fundamentally a real-AWS tool, not a local one.

**Decision: DO NOT USE — does not exist as a Terraform-native mechanism.** This confirms (rather than contradicts) the Phase 3 finding: the `strcontains()`-on-rendered-policy-JSON approach already built and verified is the correct zero-cost mechanism, because no simulator-based alternative is available inside Terraform at all.
