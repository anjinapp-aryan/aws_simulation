# ECS Execution Role vs Task Role — Traced in `modules/ecs_service/iam.tf`

The single highest-value IAM concept in this architecture, and a reliable senior-interview discriminator.

## The mental model

```
ECS / Fargate INFRASTRUCTURE                 APPLICATION CODE in the container
           │                                              │
           │ execution role                               │ task role
           ↓                                              ↓
    ECS Agent (AWS-managed)                        Your process / AWS SDK
           │                                              │
           ├── pull image from ECR                        └── whatever APIs the app calls
           ├── write container logs to CloudWatch              (S3, DynamoDB, SQS …)
           └── resolve `secrets` in the task definition
```

**Timing is the clean discriminator**: the execution role is used **before and during container startup, by AWS**. The task role is used **after startup, by your code**.

## Both roles, verbatim from source

```hcl
data "aws_iam_policy_document" "execution_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = var.execution_role_name
  assume_role_policy = data.aws_iam_policy_document.execution_assume_role.json
}

resource "aws_iam_role" "task" {
  name               = var.task_role_name
  assume_role_policy = data.aws_iam_policy_document.execution_assume_role.json   # ← same trust policy
}
```

**Note**: both roles share the *same trust policy* — both are assumed by the `ecs-tasks.amazonaws.com` service principal. The roles differ entirely in their **permissions**, not their trust. This is a detail people frequently get wrong in interviews ("the task role is assumed by the container" — no, it is assumed by the ECS service on the task's behalf).

Wired into the task definition:
```hcl
execution_role_arn = aws_iam_role.execution.arn
task_role_arn      = aws_iam_role.task.arn
```

## Execution role — what it can do

| Grant | Source | Purpose |
|---|---|---|
| `AmazonECSTaskExecutionRolePolicy` (AWS-managed) | `aws_iam_role_policy_attachment.execution_managed` | ECR pull + CloudWatch Logs write |
| `secretsmanager:DescribeSecret`, `GetSecretValue`, `ssm:GetParameter(s)` | `aws_iam_policy.execution_secrets`, **conditional** | resolve `secrets` in the task definition at startup |
| `kms:Decrypt`, `kms:DescribeKey` | same conditional policy | decrypt KMS-encrypted secrets |

Both extra statements are **conditionally created**:
```hcl
count = length(var.secret_arns) > 0 || length(var.secret_kms_key_arns) > 0 ? 1 : 0
```
…and scoped to `local.secret_policy_resources` (the specific secret ARNs) — **not `"*"`**. That is least privilege applied correctly: no secrets configured → no secrets policy exists at all.

## Task role — what it can do

By default, **almost nothing**. It gets:
| Grant | Condition |
|---|---|
| `kms:Decrypt` on one key | only if `enable_execute_command && exec_kms_key_arn != null` (ECS Exec) |
| Arbitrary caller-supplied inline policy | only if `var.task_role_policy_json != null` |

So the task role starts empty and the *caller* must explicitly grant application permissions. This is the correct default — deny by default, grant deliberately.

## Why they must be separate
If one role did both jobs, your application code would inherit the ability to pull any ECR image and read every secret referenced by the task definition. A single vulnerable dependency, SSRF bug, or RCE in the app then yields credentials that can read production secrets directly. Splitting them means a compromised application is confined to the task role's (deliberately minimal) permissions — the execution role's power was used once, by AWS, before your code ever ran, and is not available to the running process.

## Failure modes — the diagnostic table

| Broken role | Symptom | Where you see it | Task state |
|---|---|---|---|
| **Execution role** loses ECR permission | `CannotPullContainerError` | `aws ecs describe-tasks` → `stoppedReason` | never reaches RUNNING |
| **Execution role** loses CloudWatch Logs permission | container fails to start (the `awslogs` driver cannot buffer indefinitely) | `stoppedReason` | never reaches RUNNING |
| **Execution role** loses Secrets Manager/KMS permission | `ResourceInitializationError` | `stoppedReason` | never reaches RUNNING |
| **Task role** loses an application permission | `AccessDenied` from an AWS SDK call | **application logs**, at runtime | **RUNNING and healthy** |

**This table is the interview answer.** Execution-role failures are *startup* failures visible in ECS API output. Task-role failures are *runtime* failures visible only in application logs, on a task ECS considers perfectly healthy. If someone reports "the task is running but the app gets AccessDenied," the execution role is irrelevant — go straight to the task role.

## One more real detail from source
```hcl
resource "aws_ecs_service" "this" {
  ...
  depends_on = [aws_iam_role_policy_attachment.execution_managed]
}
```
The service explicitly waits for the execution role's managed policy attachment. Without it, Terraform could create the service before the policy is attached, and the first task launch would fail to pull its image — an IAM-propagation race. It needs `depends_on` because the service references the *role's* ARN (via the task definition) but never the *attachment's* output, so no implicit dependency exists.

## Memory hook
> **Execution role = AWS starting your container. Task role = your code doing its job.**
> Startup failure → execution role. Runtime `AccessDenied` → task role.
