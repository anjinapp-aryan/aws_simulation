# Terraform Concepts — Traced to Real Code

## provider
**Where**: `nonprod-app/versions.tf`
**What it means**: declares which API Terraform talks to and how (region, auth chain) — the bridge between HCL and AWS's actual API.
**How Blueprint uses it**: `required_providers { aws = { source = "hashicorp/aws", version = ">= 6.0, < 7.0" } }`, `required_version = ">= 1.8.0, < 2.0.0"`.
**Why it exists**: without a version constraint, a provider major-version bump could silently change resource schemas mid-project.
**If removed**: `terraform init` fails immediately — nothing else can run.
**Interview**: "Why pin provider versions with a range instead of an exact version?" — a range (`>=6.0,<7.0`) allows patch/minor upgrades (bug fixes) while blocking breaking major-version changes; an exact pin blocks even bug fixes.

## resource
**Where**: `modules/network/main.tf:1` — `resource "aws_vpc" "this" { ... }`
**What it means**: one real AWS object Terraform will create/manage.
**Why it exists**: the fundamental unit of infrastructure-as-code.
**If removed**: the AWS object it represents is destroyed on next apply.
**Interview**: "What's the difference between a resource and a data source?" — resource creates/owns, data source only reads.

## variable
**Where**: `modules/network/variables.tf`
**What it means**: a module's input parameter.
**How Blueprint uses it**: `private_app_nat_mode` (string, validated to one of 3 values), `availability_zones` (list), etc.
**Why it exists**: lets one module produce different infrastructure for `nonprod-app` vs `prod-app` without duplicating code.
**If removed**: the module becomes hardcoded, unusable for a second environment.
**Interview**: "How do you share one module between dev and prod?" — variables + different tfvars files per root, exactly Blueprint's pattern.

## output
**Where**: `modules/network/outputs.tf`
**What it means**: exposes a value from inside a module to whatever called it.
**How Blueprint uses it**: `internal/networking` outputs subnet IDs, which `internal/backend_edge` consumes as an input to `modules/alb`.
**Why it exists**: this is literally how cross-module dependencies are wired — Terraform has no other mechanism for one module to see another's created resource IDs.
**If removed**: the calling module can't reference anything the child module created; the dependency chain breaks at compile time (`terraform validate` fails).
**Interview**: "How does module A get a value created inside module B?" — B declares an output, A references `module.B.output_name`.

## data source
**Where**: `modules/network/main.tf:12-14` — `data "aws_availability_zones" "available" {}`; `data "aws_caller_identity" "current" {}`
**What it means**: reads existing AWS/external state, creates nothing.
**Why it exists**: avoids hardcoding AZ names (which differ per region) or account IDs (needed for ARN construction) — makes the module portable.
**If removed**: you'd have to hardcode `us-east-1a`/`us-east-1b` etc., breaking the moment you deploy to a different region.
**Interview**: "Why use `data.aws_availability_zones` instead of a hardcoded list?" — portability across regions without editing the module.

## locals
**Where**: `modules/network/main.tf:19-26` — `local.nat_gateway_count`, `local.flow_logs_name_prefix`
**What it means**: a named, computed expression — not a resource, not a variable, just a reusable calculation.
**How Blueprint uses it**: `nat_gateway_count = var.private_app_nat_mode == "required" ? length(var.availability_zones) : (...)` — the entire NAT cost/HA trade-off lives in one local.
**Why it exists**: avoids repeating the same conditional expression in every resource that needs the NAT count.
**If removed**: every NAT-related resource would need to inline the same ternary, and changing the logic would mean editing N places instead of 1.
**Interview**: "Where would you put shared computed logic used by multiple resources in a module?" — a `locals` block.
**Note — real bug found this phase**: `local.flow_logs_name_prefix` calls `trimspace(var.flow_logs_name_prefix)` without checking null first in a way that actually protects the call (see `terraform-tests-analysis.md` for the full reproduction). Locals are not automatically safe just because they look like a null-guard — HCL's evaluation order caught this repo out.

## count
**Where**: `modules/network/main.tf:172` — `aws_subnet.public_edge`, `count = length(var.availability_zones)`
**What it means**: create N indexed copies of a resource (`resource[0]`, `resource[1]`, ...).
**Why it exists**: subnets are positionally tied to a fixed AZ list.
**If removed**: you'd have to write one `aws_subnet` block per AZ manually — doesn't scale, and adding an AZ means adding a whole new resource block.
**Interview**: see `network-module-analysis.md` §12 and `interview-questions.md`.

## for_each
**Where**: `modules/network/main.tf:231` — VPC interface endpoints, keyed by service name; `modules/security_groups/main.tf:55,66` — optional dynamic egress rules
**What it means**: create N keyed copies (`resource["key"]`), addressed by a stable key instead of a position.
**Why it exists**: removing one interface endpoint from the set shouldn't perturb any of the others in state.
**If removed**: you'd need `count` instead, reintroducing the reordering-risk problem count has.
**Interview**: see `interview-questions.md` Q3.

## conditional expressions
**Where**: `modules/network/main.tf:19-22` — `private_app_nat_mode` branching
**What it means**: `condition ? true_value : false_value`, Terraform's only ternary construct.
**Why it exists**: lets one variable (`private_app_nat_mode`) drive structurally different infrastructure (0, 1, or N NAT gateways) without three separate code paths.
**If removed**: you'd need three separate resource blocks each behind a different boolean flag, more verbose and easier to get inconsistent.

## modules (and module composition)
**Where**: the entire `application_platform` → `internal/*` → leaf-module hierarchy (see `nonprod-module-dependency.md`)
**What it means**: a reusable, parameterized unit combining resources/data sources/locals.
**Why it exists**: `nonprod-app/main.tf` is one `module "app" {}` call instead of 14 separate module invocations, because `internal/*` modules do that composition once and get reused identically by both `nonprod-app` and `prod-app`.
**If removed**: `nonprod-app` and `prod-app` would each need their own full copy of every resource, guaranteed to drift apart over time.

## implicit dependencies
**Where**: ALB target group ARN (output of `internal/backend_edge`) flows into `internal/app_runtime`'s `modules/ecs_service` call as an input variable.
**What it means**: Terraform builds its execution order automatically from reference chains — no manual ordering needed.
**Why it exists**: the default and preferred mechanism; explicit ordering is a fallback for the rare case with no data reference.

## explicit dependencies (`depends_on`)
**Where**: `modules/ecs_service/service.tf` — `depends_on = [aws_iam_role_policy_attachment.execution_managed]`
**Correction from an earlier pass**: I previously stated this repo never uses `depends_on`. That was wrong — verified by re-reading `service.tf` in full this phase. It IS used, exactly once, here.
**Why it exists here specifically**: the ECS service references `aws_iam_role.execution.arn` (via the task definition), but IAM policy *attachment* is a separate resource from the role itself, and nothing in the service/task-definition block directly references the attachment's output — so Terraform's implicit-dependency inference has no data link to the attachment. Without `depends_on`, Terraform could start the ECS service before the managed execution policy is actually attached, and the service would fail to pull the image / write logs on first launch (a real IAM-propagation race condition). This is the textbook correct use of `depends_on`: a real-world ordering requirement with no natural data reference to hang it on.
**Interview**: "When do you actually need `depends_on`?" — when resource B's *success* genuinely depends on resource A being fully applied first, but B's configuration doesn't reference any of A's outputs — exactly this IAM-policy-attachment-before-first-task-launch case.

## dynamic blocks
**Where**: `modules/security_groups/main.tf:55,66` (optional egress rules); `modules/alb/main.tf` (`default_action`, two mutually-exclusive dynamic blocks toggled by `enable_origin_auth_header`); `modules/ecs_service/service.tf` (`load_balancer`, `alarms`, `service_registries`, all conditionally-present blocks)
**What it means**: generate zero-or-more nested blocks from a collection, instead of a fixed static block.
**Why it exists**: the idiom `for_each = condition ? [] : [value]` turns an optional single nested block into a for_each over a 0- or 1-element list — this exact pattern appears repeatedly across the repo, worth memorizing.
**If removed**: you'd need a static block always present, unable to conditionally omit it.

## lifecycle
**Where**: not conclusively located this phase — a targeted search is needed in Phase 2 when `modules/network`'s IGW/NAT or `modules/rds`'s instance resources are touched for real. **Correcting an earlier claim**: I previously asserted this repo uses `prevent_destroy` on RDS without having actually verified it — re-checked `modules/rds/main.tf` in full this phase and found no `lifecycle` block at all in that file. Flag this as unconfirmed, not confirmed.

## validation
**Where**: `modules/network/variables.tf:89` (`private_app_nat_mode` must be one of `required`/`canary`/`disabled`); `modules/application_platform/internal/platform_core/main.tf:88` (`enable_cost_optimized_dev_tier` must be `false` in the prod root)
**Why it exists**: fails `terraform plan`, before any AWS API call, instead of relying on documentation or code review to catch a bad config.
**Interview**: see `interview-questions.md`.

## terraform test
**Where**: `modules/network/tests/vpc_defaults.tftest.hcl`, `modules/security_groups/tests/least_privilege.tftest.hcl`
**Verified this phase**: `terraform test` on the network module actually fails — real bug, see `terraform-tests-analysis.md`. `terraform test` on security_groups was read in full and its assertions are real, specific, and meaningful (exact ingress-rule-count checks).

## terraform fmt
**Verified this phase**: `terraform fmt -check -recursive -diff` on the whole Blueprint repo → 0 diffs, exit 0. The repo is perfectly formatted.

## terraform validate
**Verified this phase**: ran against `modules/network` in isolation (`-backend=false`, no AWS credentials) → `Success! The configuration is valid.` Confirms `validate` makes zero AWS API calls — purely local syntax/type checking.

## terraform plan
Not run this phase (would require AWS credentials — permitted by the rules but not exercised, since the goal was pure local validation). Creates nothing regardless.

## remote state / state locking
**Where**: `nonprod-app/backend.tf`, `backend.hcl.example` — S3 + DynamoDB lock table pattern. Covered in depth in `local-vs-real-aws.md`.
