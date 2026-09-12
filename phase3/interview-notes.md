# Phase 3 Interview Notes — Compact Revision Summary

*Not a gate. A condensed recall sheet for later revision.*

## The one concept that matters most

> **Execution role = AWS starting your container. Task role = your code doing its job.**

| | Execution role | Task role |
|---|---|---|
| Used by | ECS agent (AWS), **before/during** startup | your application, **after** startup |
| Does | pull ECR image, write CloudWatch logs, resolve `secrets` | whatever AWS APIs the app calls |
| Failure looks like | **task never starts** — `CannotPullContainerError` / `ResourceInitializationError` in `describe-tasks` | **task RUNNING and healthy**, `AccessDenied` in *application logs* |
| Blueprint default | `AmazonECSTaskExecutionRolePolicy` + conditional secrets/KMS policy | **almost nothing** — caller must grant explicitly |

Both share the **same trust policy** (`ecs-tasks.amazonaws.com` + `sts:AssumeRole`). They differ in *permissions*, not trust. Common interview error: "the task role is assumed by the container" — no, ECS assumes it on the task's behalf.

## Trust policy vs permissions policy
- **Trust** = WHO may assume the role (`assume_role_policy`, has a `Principal`).
- **Permissions** = WHAT the role may do once assumed (no `Principal`).
- Both must allow. Most "IAM is broken" confusion is checking one and not the other.

## Policy evaluation
```
Explicit DENY  → denied, always, unoverridable
Explicit ALLOW → allowed
Nothing        → denied (implicit)
```
`Deny` carves exceptions out of a broad `Allow`; you never need it to block something never granted. Blueprint contains **zero** explicit `Deny` — everything is narrow-allow + implicit deny.

## Least privilege — the testing insight
> **Least privilege is proven by counting what is absent.** `== 1` is a security test; `>= 1` is a smoke test.

`least_privilege.tftest.hcl` asserts **exactly one** 3306 ingress rule. That fails the instant someone adds a second/wider rule. **5 passed, 0 failed** (verified this phase).

## SG-to-SG vs CIDR
`source_security_group_id` beats `cidr_blocks` because a CIDR rule grants access to *whatever occupies that range in future*; an SG reference grants access to *a specific identity*. Also survives renumbering and self-documents intent.

## The three-layer defence on RDS
1. `private_db` route table has **no internet route in any NAT mode** (no path)
2. RDS SG ingress only from backend SG (no permission)
3. `publicly_accessible = false`

## Diagnostic discriminators (the highest-value recall items)
| Error | Means |
|---|---|
| `AccessDenied` | **IAM** |
| timeout / hang | **network** — SG or NACL dropped it |
| connection refused | reached the host, nothing listening |
| auth failed | credentials, not network |
| task won't start | **execution** role / endpoint |
| task RUNNING + AccessDenied | **task** role |
| "internet broken, AWS services fine" | NAT (endpoints bypass it) |
| `AccessDenied` with perfect IAM | **VPC endpoint policy** blocking it |

## Two real `depends_on` cases in this repo
1. `aws_ecs_service` → `aws_iam_role_policy_attachment.execution_managed` (IAM propagation race — service references the *role*, not the *attachment*)
2. `aws_nat_gateway` → `aws_internet_gateway` (NAT needs IGW attached first, no data reference exists)

Both are the legitimate pattern: **real ordering requirement, no data reference to hang it on**.

## Hard-won methodology lessons from this phase
1. **Reading a test proves nothing about whether it passes.** I cited `least_privilege.tftest.hcl` as evidence in two phases without running it.
2. **Run the project's own pinned toolchain.** I ran TF 1.9.8 against a repo whose CI pins 1.13.1, concluded the repo was systemically broken, and was wrong. On 1.13.1: **77 tests, 0 failures.**
3. **`terraform validate` passing ≠ `terraform test` passing.** Validate doesn't exercise expression evaluation; that's why the version problem hid for two phases.
4. **Verify claims about tooling limits.** I asserted Terraform "structurally prevents" IAM assertions — then disproved it in one experiment.

## Quotable one-liners
- "Execution role failures are startup failures. Task role failures are runtime failures on a healthy task."
- "Least privilege is a claim about absence, so assert the count."
- "A CIDR rule grants access to an address; an SG reference grants access to an identity."
- "AccessDenied is IAM. Timeout is network. Never conflate them."
