# IAM Fundamentals — Answered as WHO / WHAT / WHICH RESOURCE / UNDER WHAT CONDITION

Not definitions in isolation — every concept is answered against real Blueprint code.

## The four questions every IAM policy answers
```
WHO?                  → Principal (trust policy) / the role holder (permissions policy)
WHAT?                 → Action
TO WHICH RESOURCE?    → Resource
UNDER WHAT CONDITION? → Condition
```

## Trust policy vs permissions policy — the distinction people get wrong

| | Trust policy | Permissions policy |
|---|---|---|
| Answers | **WHO may become this role** | **WHAT the role may do once assumed** |
| Terraform field | `assume_role_policy` on `aws_iam_role` | `aws_iam_role_policy` (inline) / `aws_iam_role_policy_attachment` (managed) |
| Has a `Principal` | **Yes — mandatory** | No (the principal is implicitly the role) |
| Blueprint example | `data.aws_iam_policy_document.execution_assume_role` — principal `ecs-tasks.amazonaws.com`, action `sts:AssumeRole` | `AmazonECSTaskExecutionRolePolicy` attached to the execution role |

Both must permit the operation. A role with perfect permissions that nobody can assume is inert; a role anyone can assume with no permissions is harmless. **Most "IAM doesn't work" confusion is checking one and not the other.**

## Principal
*WHO.* In Blueprint, always an AWS **service** principal, never a user:
```hcl
principals {
  type        = "Service"
  identifiers = ["ecs-tasks.amazonaws.com"]     # ECS task roles
}
# also in this repo:
#   "vpc-flow-logs.amazonaws.com"    → modules/network, flow logs role
#   "monitoring.rds.amazonaws.com"   → modules/rds, enhanced monitoring role
```
Each is the AWS service that will call `sts:AssumeRole` on your behalf. Note there are **no IAM users anywhere in this repo** — a good production signal; humans and services use roles, not long-lived user credentials.

## AssumeRole and STS
`sts:AssumeRole` is the only action in every trust policy here. The flow:
```
ECS needs to start a task
   ↓
calls sts:AssumeRole against the execution role
   ↓
trust policy check: is ecs-tasks.amazonaws.com allowed? → yes
   ↓
STS returns temporary credentials (expiring, auto-rotated)
   ↓
ECS agent uses them to pull the image / fetch secrets
```
The value: **no static credentials exist anywhere.** Nothing to leak, nothing to rotate manually. This is why "use roles, not access keys" is the standing advice.

## Action
*WHAT.* Blueprint scopes actions tightly rather than using wildcards. From `modules/network`'s `local.interface_endpoint_actions`:
```hcl
"ecr.api" = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage",
             "ecr:DescribeImages", "ecr:DescribeRepositories",
             "ecr:GetAuthorizationToken", "ecr:GetDownloadUrlForLayer"]
"kms"     = ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", ...]
```
Six named ECR actions rather than `ecr:*` — enumerated deliberately.

## Resource
*TO WHICH RESOURCE.* The execution-secrets policy scopes to `local.secret_policy_resources` (the actual secret ARNs), not `"*"`. Where a wildcard is genuinely unavoidable, the repo documents why:
```hcl
#tfsec:ignore:aws-iam-no-policy-wildcards CloudWatch Logs stream ARNs require
# wildcard suffixes and cannot be enumerated ahead of time.
Resource = "${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"
```
Note that even this "wildcard" is scoped to one specific log group's ARN prefix — not a bare `"*"`. **Suppressing a linter with a written justification is good practice; suppressing it silently is not.**

## Condition
*UNDER WHAT CONDITION.* From the S3 gateway endpoint policy:
```hcl
condition {
  test     = "StringEquals"
  variable = "aws:PrincipalAccount"
  values   = [data.aws_caller_identity.current.account_id]
}
```
This is a **resource policy** on the endpoint that refuses use by any principal outside this account — even though the statement's `Principal` is `"*"`. A naive reading of `Principal = "*"` looks alarming; the condition is what makes it safe. Reading `Principal` without reading `Condition` is a classic review error.

## Identity policy vs resource policy
| | Identity-based | Resource-based |
|---|---|---|
| Attached to | a role/user/group | the resource itself |
| Needs `Principal`? | No | **Yes** |
| Blueprint examples | everything in `modules/ecs_service/iam.tf` | VPC endpoint policies in `modules/network`; SQS/S3 bucket policies elsewhere |
For cross-account access, **both** sides must allow it. Within one account, either can suffice.

## Managed vs inline policies
| | Managed | Inline |
|---|---|---|
| Lifecycle | standalone object, attachable to many roles | lives and dies with its one role |
| Blueprint | `AmazonECSTaskExecutionRolePolicy` (AWS-managed, attached); `aws_iam_policy.execution_secrets` (customer-managed) | 11 × `aws_iam_role_policy` |
| Use when | shared across roles, or AWS provides a good one | permissions are genuinely specific to one role |
Blueprint uses AWS-managed where AWS's policy is correct (the ECS execution policy is well-scoped), and customer-managed/inline for anything bespoke — a reasonable split.

## Policy evaluation (the rule that decides everything)
```
Explicit DENY anywhere        → DENIED. Always. Nothing overrides it.
   ↓ (no explicit deny)
Explicit ALLOW present        → ALLOWED
   ↓ (no allow)
Default                       → DENIED  (implicit deny)
```
Consequences worth stating: an explicit `Deny` cannot be overridden by any `Allow`, in any policy, ever. And "no policy mentions this action" means denied — you never need a `Deny` to block something that was never allowed. `Deny` is for carving exceptions out of a broad `Allow`, not for general blocking.

Blueprint contains **no explicit `Deny` statements** — everything is allow-scoped-narrowly, relying on implicit deny. That is the simpler and generally preferable design.

## Least privilege in one line
> Grant the **narrowest Action** on the **narrowest Resource**, to the **narrowest Principal**, under the **tightest Condition** that still lets the job work — and create nothing at all when nothing is needed (Blueprint's `count = length(var.secret_arns) > 0 ? 1 : 0` is least privilege expressed in Terraform).

## AccessDenied troubleshooting order
1. **Which identity?** Execution role or task role? (Startup failure → execution; runtime → task. See `execution-vs-task-role.md`.)
2. **Trust or permissions?** Can the principal assume the role at all, or can it assume it but lacks the action?
3. **Read the error message** — AWS names the principal, action, and resource. It is unusually specific; use it rather than guessing.
4. **Explicit deny?** Check for a `Deny`, a permission boundary, or an SCP.
5. **Condition mismatch?** Right action and resource, but a condition (account, source ARN, tag) is unsatisfied.
6. **Is it actually IAM?** `AccessDenied` = IAM. **Timeout = network.** Never conflate them (see `failure-scenarios.md`).
7. **Endpoint policy?** In this architecture an interface-endpoint policy can produce `AccessDenied` even when IAM is perfect — because the request is blocked at the VPC endpoint, not by IAM.
