# Phase 3 Simulation & Verification Results

All results below are from commands actually executed this phase. Zero AWS resources created, zero AWS API calls, zero cost.

---

## ⚠️ RESULT 1 — The most important finding: my Phase 1 and Phase 2 conclusions were WRONG

### What I previously reported
- **Phase 1**: "Found a real bug — `modules/network`'s own test suite fails. `trimspace(null)` in a locals null-guard."
- **Phase 2**: "Root cause proven: HCL evaluates both operands of `&&`. **Classification: Terraform/HCL language behaviour — not repo-specific, not environment-specific.**"

### What is actually true
**The repository is not buggy. My Terraform version was wrong.**

| Terraform version | `null != null && trimspace(null) != ""` |
|---|---|
| **1.9.8** (what I was running) | **ERROR** — `Invalid value for "str" parameter: argument must not be null` |
| **1.13.1** (what the repo's CI pins) | **`false`** — short-circuits correctly |

Evidence for the pinned version: `.github/actions/setup-terraform/action.yml` → `terraform-version: default: "1.13.1"`.

### Full test suite, both versions

| Module | TF 1.9.8 | TF 1.13.1 |
|---|---|---|
| alb | 0 passed, 1 failed, 1 skipped | **2 passed, 0 failed** |
| application_platform | 0 passed, 1 failed, 6 skipped | **7 passed, 0 failed** |
| .../operational_observability | 2 passed, 0 failed | 2 passed, 0 failed |
| .../policy_assembly | 1 passed, 0 failed | 1 passed, 0 failed |
| backup_baseline | 0 passed, 1 failed, 2 skipped | **3 passed, 0 failed** |
| budget_alerts | 3 passed, 0 failed | 3 passed, 0 failed |
| cloudfront_backend | 0 passed, 1 failed, 2 skipped | **3 passed, 0 failed** |
| cloudfront_frontend | 0 passed, 1 failed, 2 skipped | **3 passed, 0 failed** |
| ecr | 3 passed, 0 failed | 3 passed, 0 failed |
| ecs_backend | 0 passed, 1 failed, 2 skipped | **3 passed, 0 failed** |
| ecs_service | 0 passed, 1 failed, 3 skipped | **4 passed, 0 failed** |
| guardduty_member_detector | 1 passed, 0 failed | 1 passed, 0 failed |
| network | 0 passed, 1 failed, 11 skipped | **12 passed, 0 failed** |
| rds | 0 passed, 1 failed, 12 skipped | **13 passed, 0 failed** |
| s3 | 0 passed, 1 failed, 8 skipped | **9 passed, 0 failed** |
| security_baseline | 0 passed, 1 failed, 2 skipped | **3 passed, 0 failed** |
| security_groups | 0 passed, 1 failed, 4 skipped | **5 passed, 0 failed** |
| **TOTAL** | **10 passed, 12 suites failing** | **77 passed, 0 failed** |

### The genuine (much smaller) finding that survives
`versions.tf` declares `required_version = ">= 1.8.0, < 2.0.0"`, but the code depends on `&&` short-circuit evaluation, which does not exist in 1.8.x/1.9.x. **The version constraint is too permissive.** Anyone on a Terraform version the constraint explicitly permits (1.8.0–~1.9.x) hits immediate, confusing failures across 12 of 17 modules. The correct constraint would pin the minimum to whichever release introduced short-circuit evaluation.

That is a real, reportable bug — but it is a *version-constraint* bug, not the "systemic broken idiom across 24 occurrences" I was about to report.

### Process lesson
I praised `least_privilege.tftest.hcl` as proof of rigorous testing in Phase 1 and Phase 2 **without ever executing it** — I only read it. When I finally ran it this phase, it failed, and I nearly reported the repo as broken. Both the original praise and the near-retraction were unfounded: **reading a test proves nothing about whether it passes; running it on the wrong toolchain proves nothing about whether the code is correct.** Verify with the project's own pinned toolchain before drawing conclusions.

---

## RESULT 2 — The IAM testing gap: real, but a choice rather than a technical limit

### Static analysis (version-independent)
Across all 17 `.tftest.hcl` files:
- **Exactly one** IAM-related assertion exists: `modules/rds/tests/production_defaults.tftest.hcl` → `condition = length(aws_iam_role.enhanced_monitoring) == 1`. That is an **existence/count check**, not a permissions check.
- **Zero** assertions anywhere about trust-policy principals, action scope, resource scope, conditions, or the task-role/execution-role boundary.
- **7 test files** mock the policy data source with an empty statement list:
  ```hcl
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  ```
  Within those files, the module's real policy logic is replaced by an empty document before any assertion could inspect it.

Compare: `modules/security_groups/tests/least_privilege.tftest.hcl` has 5 runs with exact ingress-rule-count assertions — and **all 5 pass on 1.13.1**. SG least privilege is genuinely well tested.

**Conclusion: the asymmetry is real. SG least privilege is asserted; IAM least privilege is not asserted anywhere.**

### Experiment — is IAM assertion technically possible in `terraform test`?
Built a minimal scratch module reproducing Blueprint's conditional-secrets-policy pattern, with a test that does **not** mock `aws_iam_policy_document`, using a credential-free provider config:
```hcl
provider "aws" {
  region = "eu-west-1"
  access_key = "test"
  secret_key = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}
```
Assertions tested:
1. `strcontains(aws_iam_policy.execution_secrets[0].policy, "secretsmanager:GetSecretValue")` → **pass**
2. `!strcontains(aws_iam_policy.execution_secrets[0].policy, "\"Resource\": \"*\"")` → **pass**

Result: `Success! 2 passed, 0 failed.` — **zero AWS credentials, zero AWS API calls.**

**Conclusion**: `aws_iam_policy_document` is rendered locally by the provider (it is a document generator, not an API call), so real IAM policy JSON **can** be asserted at plan time for free. The gap in Blueprint is therefore a **design choice in how its tests mock the provider**, not a limitation of Terraform. This makes the missing piece very small to add.

---

## RESULT 3 — `terraform fmt` / `validate`
- `terraform fmt -check -recursive` across the whole Blueprint: **clean, 0 diffs** (re-confirmed).
- `terraform validate` passes on `modules/network` and `modules/security_groups` on both Terraform versions — confirming `validate` does not exercise the expression evaluation that `test` does, which is exactly why the version problem stayed invisible in Phases 1–2.

---

## Commands executed this phase
```bash
terraform init -backend=false          # per module, both TF versions
terraform validate                     # modules/network, modules/security_groups
terraform test                         # all 17 modules × 2 Terraform versions
terraform console                      # short-circuit experiments, both versions
# scratchpad-only: minimal IAM assertion module + test
```
No `plan`, no `apply`, no `destroy`, no AWS credentials configured, no AWS resources created. **Total AWS spend: $0.00.**
