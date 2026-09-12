# Least Privilege — What the Test Actually Proves

## The test: `modules/security_groups/tests/least_privilege.tftest.hcl`
**Status: executed this phase for the first time — 5 passed, 0 failed on Terraform 1.13.1.**
(It fails on 1.9.8 for an unrelated toolchain reason — see `simulation-results.md`. In Phases 1–2 I cited this test as evidence without ever running it, which was a methodology error.)

## What each assertion proves — and what it does *not*

```hcl
run "rds_ingress_restricted_to_backend_only" {
  command = plan
  assert {
    condition = length([
      for rule in aws_security_group.rds.ingress : rule
      if rule.from_port == 3306 && rule.to_port == 3306 && rule.protocol == "tcp"
    ]) == 1
    error_message = "RDS security group should allow exactly one TCP ingress rule on port 3306."
  }
}
```

| Assertion | Proves | Does **not** prove |
|---|---|---|
| exactly **one** 3306 ingress rule on the RDS SG | no second/duplicate/wider rule was added | that the one rule points at the *right* source |
| exactly one app-port ingress on the backend SG | ECS is not reachable from multiple sources | that the ALB can actually reach it at runtime |
| exactly one 443 ingress on the ALB SG | the public entry point is exactly as wide as intended | that TLS is configured correctly |
| `app_port` change propagates to backend SG + ALB egress, **RDS egress stays 3306** | no accidental coupling between unrelated ports | anything about runtime traffic |
| env suffix applied to SG names | no cross-environment name collision in a shared account | — |

### The key design insight: `== 1`, not `>= 1`
Asserting **exactly one** is what makes this a least-privilege test rather than a smoke test. `>= 1` would pass even after someone adds `cidr_blocks = ["0.0.0.0/0"]` as a second rule. `== 1` fails the moment the surface widens. **Least privilege is a statement about what is *absent*, so the assertion must be about count, not existence.**

### What it fundamentally cannot prove
`command = plan` with a mocked provider asserts on **planned configuration**, never on **AWS runtime behaviour**. It proves the *intent* encoded in Terraform is correct. It cannot prove AWS enforced it, that the SG was attached to the right ENI, or that traffic actually flows. That requires real AWS — deferred to Phases 5/6 per the roadmap.

## Least privilege elsewhere in the repo (beyond this test)

**Conditional creation — the strongest form:**
```hcl
count = length(var.secret_arns) > 0 || length(var.secret_kms_key_arns) > 0 ? 1 : 0
```
No secrets configured → the secrets policy **does not exist**. Not "exists but empty" — absent. The narrowest possible permission is none.

**Enumerated actions instead of wildcards** (`local.interface_endpoint_actions`): six named ECR actions rather than `ecr:*`.

**Scoped resources**: the execution-secrets policy targets `local.secret_policy_resources` (specific ARNs), not `"*"`.

**Documented wildcard exceptions**: where a wildcard is genuinely required, it is justified inline —
```hcl
#tfsec:ignore:aws-iam-no-policy-wildcards CloudWatch Logs stream ARNs require
# wildcard suffixes and cannot be enumerated ahead of time.
Resource = "${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"
```
…and even then scoped to one log group's ARN prefix, not a bare `"*"`.

**Identity over address**: SG-to-SG references rather than CIDR rules (see `security-groups.md`).

**Default-SG lockdown**: `aws_default_security_group.lockdown` strips all rules, so the fallback for an unconfigured resource is no access.

## The asymmetry
All of the above is *implemented*. Only the **Security Group** half is *asserted*. There is no equivalent test for any IAM property — full proof in `iam-testing-gap.md`. The defensive value of `== 1` on an SG rule is exactly the value that IAM lacks today: nothing stops a future PR from widening a role.

## Memory hook
> **Least privilege is proven by counting what is absent, not by checking what exists.**
> `== 1` is a security test. `>= 1` is a smoke test.
