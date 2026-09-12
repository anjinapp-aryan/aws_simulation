# Senior-Level Interview Questions — Grounded in Verified Repo Evidence

**Q: Why use modules instead of one flat root?**
A: Reuse without duplication — `nonprod-app` and `prod-app` share every module byte-for-byte, differing only in tfvars (verified via diff in `cheap-vs-ha.md`). A flat root would mean copy-pasting the entire VPC/ALB/ECS/RDS config twice, guaranteed to drift.

**Q: `count` vs `for_each` — when would you pick each, concretely?**
A: `count` for positionally-meaningful, rarely-reordered collections (this repo's AZ-indexed subnets — verified in `modules/network/main.tf:172`). `for_each` for independently-addressable items where losing/adding one shouldn't disturb the others (this repo's VPC interface endpoints, keyed by service name — verified at `main.tf:231`). Picking `count` for the endpoints would mean removing "kms" from the middle of the list reshuffles every endpoint after it in state.

**Q: How does Terraform determine resource/module dependency order?**
A: By tracing reference expressions — if module B's input variable is set to `module.A.some_output`, B implicitly depends on A. Verified concretely this phase: `internal/backend_edge` receives `vpc_id`/`alb_subnet_ids` from `internal/networking`'s outputs, so Terraform orders networking before backend_edge automatically, no `depends_on` needed.

**Q: When would you actually need `depends_on`?**
A: When resource B's correctness genuinely requires resource A to be fully applied, but B's config contains no data reference to A. Verified real example this phase: `aws_ecs_service.this` has `depends_on = [aws_iam_role_policy_attachment.execution_managed]` — the service references the execution *role's* ARN, but not the policy *attachment*, so without the explicit dependency, ECS could try to start tasks before the managed policy is actually attached to that role (a real IAM-propagation race).

**Q: How do you prevent accidental production destruction?**
A: Layered: `deletion_protection` on RDS (a real, non-hardcoded variable, verified in `modules/rds/main.tf`), mandatory final-snapshot naming via `coalesce()` so a snapshot always exists unless explicitly skipped, and process-level guardrails like requiring a `terraform plan` review before `apply` in CI (`.github/workflows/pr-plan.yml`).

**Q: How do you manage Terraform state safely in a team?**
A: Remote backend (S3) + locking (DynamoDB conditional-write as mutex) — verified present in `nonprod-app/backend.tf`/`backend.hcl.example`, though not exercised against real AWS this phase. Local state is fine solo, breaks down the moment two people might `apply` concurrently.

**Q: How do you detect drift?**
A: Scheduled `terraform plan` in CI, diffed against expected-empty — verified present as `.github/workflows/drift-detection.yml`. A non-empty plan on a schedule means someone changed something outside Terraform (console click-ops), or Terraform's own state has diverged from reality.

**Q: How would you structure Terraform for dev/stage/prod?**
A: This repo's actual answer (not a textbook one): separate root directories (`nonprod-app`/`prod-app`) each calling the *same* shared module tree, differing only via `terraform.tfvars`, each with its own state backend. Not workspaces, not branches — separate roots, separate state, shared modules.

**Q: How would you safely control NAT Gateway cost?**
A: A 3-valued mode variable driving a `count`-based `local.nat_gateway_count` (verified: `required`=1-per-AZ, `canary`=1-shared, `disabled`=0), paired with VPC interface endpoints so ECR/logs/secrets/KMS/STS traffic never needs NAT/internet at all even in `disabled` mode — meaning "no NAT" doesn't mean "ECS breaks," verified via the exact `interface_endpoint_actions` map covering precisely those services.

**Q: What is the difference between ECS task role and execution role?**
A: Execution role = what the ECS *agent* needs (pull image, write logs, fetch secrets at startup) — gets AWS's managed `AmazonECSTaskExecutionRolePolicy`. Task role = what the *application code* needs at runtime, scoped only to what you explicitly grant. Verified via full read of `modules/ecs_service/iam.tf`: the execution role's extra permissions are conditionally added only if secrets are actually referenced; the task role starts with nothing beyond the base assume-role policy unless the caller supplies an inline policy or enables ECS Exec.

**Q: Why can an ALB return 503 even when ECS tasks show RUNNING?**
A: `RUNNING` is an ECS-API-level state — it doesn't mean the ALB's health check is passing, nor that the app is actually serving correct responses. Verified concretely: this repo's `deployment_circuit_breaker` + ALB-level CloudWatch alarms (`deploy_5xx`, `deploy_unhealthy_hosts`, both in `autoscaling.tf`) exist specifically because ECS-level health isn't sufficient signal — a bad deploy can pass ECS's own checks while still failing at the ALB/application level, which is exactly why the rollback trigger is wired to ALB metrics, not just ECS task state.

**Q: Given the module hierarchy is 3 levels deep (root → application_platform facade → internal/* composition → leaf modules), what's the trade-off of that design?**
A: Verified via actually tracing it this phase (took multiple greps to reconstruct): it buys `nonprod-app`/`prod-app` a single, simple `module "app" {}` call each, keeping the two roots structurally identical and hard to accidentally drift apart. It costs a first-time reader real effort — I had to grep every `source =` line in the repo to build an accurate dependency diagram, because the facade layer obscures which leaf module actually creates what. A senior engineer should recognize this as a deliberate trade-off (root simplicity vs. discoverability), not a design flaw.
