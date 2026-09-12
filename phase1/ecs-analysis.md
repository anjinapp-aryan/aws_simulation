# `modules/ecs_service/` — Deep Trace (all 5 files read in full this phase)

## ECS Cluster
Not created by this module — `var.cluster_arn`/`var.cluster_name` are inputs. The cluster itself lives in `modules/ecs_backend` (called from `internal/app_runtime`, sibling to this module). This module (`ecs_service`) only creates the *service* and *task definition* layer, deliberately separated from cluster-level resources.

## ECS Task Definition (`task_definition.tf`)
```hcl
resource "aws_ecs_task_definition" "this" {
  family, network_mode = "awsvpc", requires_compatibilities = ["FARGATE"],
  cpu = tostring(var.task_cpu), memory = tostring(var.task_memory),
  execution_role_arn = aws_iam_role.execution.arn,
  task_role_arn      = aws_iam_role.task.arn,
  container_definitions = jsonencode([local.container_definition])
  runtime_platform { cpu_architecture = var.task_cpu_architecture, operating_system_family = "LINUX" }
}
```
Defaults (`variables.tf`): `task_cpu=512`, `task_memory=1024`, `task_cpu_architecture="ARM64"` (Graviton — cheaper Fargate pricing tier, a deliberate cost choice, not an accident), `desired_count=1`.

## Container definition (`locals.tf`)
Built by `local.container_definition`, a `merge()` of a base object plus conditionally-added keys (`user`, `entryPoint`, `command`, `healthCheck` — each added only `if` the corresponding variable is non-empty, the same "optional key via merge+conditional" idiom as the dynamic-block pattern elsewhere). Image comes from `var.container_image` (a plain string — the ECR image URI, supplied by the caller, meaning this module has zero opinion about *how* the image got into ECR, only that a URI is handed to it). Port mapping: `containerPort = hostPort = var.container_port` (required for `awsvpc` network mode — host and container ports must match since there's no port remapping in that mode).

## Execution Role vs Task Role (`iam.tf`, verified in full — the single most important distinction in this module)
| | Execution Role | Task Role |
|---|---|---|
| Who assumes it | ECS agent, before/during container startup | the application code running inside the container |
| What it's for | pull the image from ECR, write logs to CloudWatch, fetch secrets referenced in the task definition | whatever AWS APIs the *application* needs to call at runtime (S3, DynamoDB, etc.) |
| Managed policy attached | `AmazonECSTaskExecutionRolePolicy` (AWS-managed) | none by default — only what you explicitly grant |
| Extra grants in this module | `execution_secrets` policy, conditionally created (`count = length(var.secret_arns)>0 || length(var.secret_kms_key_arns)>0 ? 1:0`) — `secretsmanager:GetSecretValue`/`ssm:GetParameter`/`kms:Decrypt` | `task_exec_kms` (only if ECS Exec + a KMS key are both enabled) + `task_role_policy_json` (arbitrary caller-supplied inline policy) |
**Why two roles, not one**: separation of concerns and blast-radius limiting — if application code is compromised (e.g. a dependency vulnerability), it only has whatever the *task role* grants it, never the execution role's ECR-pull/secret-fetch permissions, which the app never legitimately needs at runtime (those happened once, at container start, by the ECS agent, not the app).

## ECS Service (`service.tf`, verified in full)
- `launch_type = "FARGATE"`, `desired_count = var.desired_count`
- **`deployment_circuit_breaker { enable = true, rollback = true }`** — real, present unconditionally. This means a failing deployment (tasks that never reach healthy) automatically rolls back to the previous task definition, without human intervention.
- **`dynamic "alarms"`** — when `local.enable_deploy_alarms` is true, wires two CloudWatch alarms (`deploy_5xx`, `deploy_unhealthy_hosts`, both in `autoscaling.tf`) directly into the deployment's rollback trigger — meaning a deploy can auto-rollback not just on ECS-level health-check failure but on *ALB-level* 5xx-rate or unhealthy-host-count breach, a tighter and more realistic production safety net.
- **`network_configuration { subnets = var.private_subnet_ids, security_groups = var.service_security_group_ids }`** — tasks run in private subnets, never public.
- **`depends_on = [aws_iam_role_policy_attachment.execution_managed]`** — real, explicit, and the correct use case (see `terraform-concepts.md` for why this specific dependency needs to be explicit rather than implicit).
- `load_balancer`/`service_registries` blocks are both dynamic/optional, keyed off whether a target group ARN or service-discovery registry ARN was actually supplied.

## Autoscaling (`autoscaling.tf`, verified in full)
Three independent target-tracking policies, all optional/composable:
1. CPU target tracking (`ECSServiceAverageCPUUtilization`)
2. Memory target tracking (`ECSServiceAverageMemoryUtilization`)
3. ALB request-count-per-target tracking (`ALBRequestCountPerTarget`) — **only created if both `alb_request_count_target_value` and `target_group_arn_suffix` are supplied** (`count = ... != null ? 1 : 0`) — this is the most production-realistic of the three, since CPU/memory can be misleading proxies for actual load on an I/O-bound service, while requests-per-target scales directly on what the ALB is actually seeing.

## Logging (`logging.tf`)
`aws_cloudwatch_log_group.this` — one group per service, `retention_in_days = var.log_retention_days` (not hardcoded — a real cost control, since indefinite retention silently accumulates storage cost). Optional second log group (`exec`) only created if ECS Exec is enabled, kept separate from application logs (so interactive debug-session logs don't mix with app output).

## Why the deployment_circuit_breaker + alarms combo directly answers "ALB 503 despite ECS tasks RUNNING"
A task can report `RUNNING` at the ECS API level while still being functionally broken (e.g. it started but can't reach its database, so every request errors). The ALB-level alarms (5xx count, unhealthy host count) catch exactly this gap between "ECS thinks it's running" and "the ALB is actually getting good responses from it" — and trigger automatic rollback rather than leaving a broken deployment serving live traffic indefinitely.
