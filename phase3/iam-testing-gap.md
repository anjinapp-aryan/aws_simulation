# The IAM Testing Gap — Proven from Source

## The claim under investigation
> "Blueprint has strong Security Group test coverage but almost no meaningful IAM permission assertions."

Per the phase instruction, this was **not** taken on trust. Verified directly.

## Verdict: **CONFIRMED — but with an important correction to the stated mechanism.**

## Evidence A — the asymmetry is real

**Security Groups** (`modules/security_groups/tests/least_privilege.tftest.hcl`) — 5 runs, all passing on TF 1.13.1:
| Assertion | Kind |
|---|---|
| RDS SG has **exactly one** TCP/3306 ingress rule | least-privilege (exact count) |
| Backend SG has **exactly one** app-port ingress rule | least-privilege (exact count) |
| ALB SG has **exactly one** TCP/443 ingress rule | least-privilege (exact count) |
| Custom `app_port` propagates to backend SG + ALB egress, **but RDS egress stays 3306** | coupling isolation |
| Environment suffix applied to SG names | naming |

**IAM** — across all 17 test files, exactly one IAM assertion exists:
```hcl
# modules/rds/tests/production_defaults.tftest.hcl
condition = length(aws_iam_role.enhanced_monitoring) == 1
```
That asserts the role **exists**. It asserts nothing about what the role can *do*.

**Nothing anywhere asserts**: trust-policy principal, permitted actions, resource scope, conditions, or — most importantly — the **task-role/execution-role boundary**.

## Evidence B — the mocking mechanism, and the correction

7 test files contain:
```hcl
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}
```

The chain, as originally hypothesised:
```
Real IAM policy logic
      ↓
data.aws_iam_policy_document
      ↓
mock_provider replaces it
      ↓
empty Statement[]
      ↓
permission logic disappears
      ↓
test cannot prove least privilege
```

**This chain is accurate for those 7 files.** Within them, policy content genuinely cannot be asserted, because the document is replaced before evaluation.

### The correction: this is a *choice*, not a Terraform limitation
I initially framed this as Terraform structurally preventing IAM testing. **That framing is wrong**, and I disproved it with an experiment (full detail in `simulation-results.md`).

`data "aws_iam_policy_document"` is **rendered locally by the AWS provider** — it is a JSON document generator, not an API call. So a test that simply *does not mock it*, using a credential-free provider block, can assert on the real rendered policy JSON:

```hcl
provider "aws" {
  region                      = "eu-west-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

run "policy_is_not_wildcard_resource" {
  command = plan
  assert {
    condition     = !strcontains(aws_iam_policy.execution_secrets[0].policy, "\"Resource\": \"*\"")
    error_message = "Policy must not use a wildcard resource."
  }
}
```
**Verified result: `Success! 2 passed, 0 failed`, with zero AWS credentials and zero API calls.**

## Why Blueprint mocks it anyway (the charitable, probably-correct reading)
The modules that mock `aws_iam_policy_document` also use `data.aws_caller_identity` and `data.aws_region`, which **do** require provider credentials/config. `mock_provider` is the blunt instrument that makes the whole module planable offline in one line. Mocking the policy document is likely collateral damage from mocking the provider wholesale, not a deliberate decision to avoid IAM assertions.

## Why this matters (production consequence)
The task-role/execution-role split is the single most security-relevant design decision in `modules/ecs_service/iam.tf`. Today, nothing prevents a future PR from adding `secretsmanager:GetSecretValue` to the **task** role — which would quietly hand every line of application code the ability to read startup secrets directly, defeating the separation. The SG equivalent of that mistake (a second, wider ingress rule) **would** be caught, by a test that already exists and already passes.

## The smallest thing that closes the gap
One `.tftest.hcl` for `modules/ecs_service`, in the same spirit as `least_privilege.tftest.hcl`, asserting the role boundary. Candidate assertions:
1. The **task role** must not grant `ecr:*`, `secretsmanager:GetSecretValue`, or `logs:CreateLogStream` — those belong to the execution role.
2. The **execution role**'s secrets policy must scope `Resource` to the supplied secret ARNs, never `"*"`.
3. Both roles' trust policies must name exactly `ecs-tasks.amazonaws.com` as principal.

This is a test addition, **not** a change to any production Terraform — consistent with the rule against modifying working modules.

**Not built this phase** (Phase 3 is study + audit; building is the next decision point, and it would mean writing a file into the vendored Blueprint clone, which needs your go-ahead).
