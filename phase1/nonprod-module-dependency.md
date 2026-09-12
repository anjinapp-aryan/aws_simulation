# `nonprod-app` Module Dependency Graph — Verified Against Actual `source =` References

**This corrects the Phase-0 diagram**, which wrongly assumed `nonprod-app/main.tf` calls `network`/`alb`/`ecs_service`/`rds` directly. Verified by grepping every `source =` line in the repo this phase: `nonprod-app/main.tf` has exactly **one** module call.

```
nonprod-app/main.tf
  └─→ module "app"  (source = ../modules/application_platform)
        │
        ├─→ internal/deployment_contract    (naming/mode resolution — no AWS resources)
        ├─→ internal/platform_core          (account IAM/KMS scaffolding + cost-tier validation guard)
        ├─→ internal/access_log_storage     (S3 log buckets, + DR replica)
        ├─→ internal/networking
        │     ├─→ ../../../network            (modules/network — VPC, subnets, NAT, endpoints)
        │     └─→ ../../../security_groups      (modules/security_groups — ALB/backend/RDS SGs)
        ├─→ internal/backend_edge
        │     └─→ ../../../alb                 (modules/alb — listener, target group, health check)
        ├─→ internal/frontend_storage
        │     └─→ ../../../s3                  (modules/s3 — frontend static asset bucket)
        ├─→ internal/edge_contract           (routing decisions between frontend/backend)
        ├─→ internal/frontend_edge
        │     └─→ ../../../cloudfront_frontend
        ├─→ internal/frontend_origin_access  (CloudFront OAC wiring)
        ├─→ internal/app_data
        │     └─→ ../../../rds                 (modules/rds — subnet group, instance, secret rotation)
        ├─→ internal/policy_assembly         (assembles IAM policy JSON fragments)
        ├─→ internal/platform_governance
        │     ├─→ ../../../guardduty_member_detector
        │     ├─→ ../../../security_baseline
        │     ├─→ ../../../backup_baseline
        │     └─→ ../../../budget_alerts       (cost-safety layer)
        ├─→ internal/app_runtime
        │     ├─→ ../../../ecr                 (modules/ecr — image repository)
        │     ├─→ ../../../ecs_backend          (modules/ecs_backend — cluster-level resources)
        │     └─→ ../../../ecs_service          (modules/ecs_service — task def, service, IAM, autoscaling)
        └─→ internal/operational_observability (CloudWatch alarms + alarm-naming test)
```

## Refined dependency chains (module-output → module-input, not just call-graph position)

**Network chain**:
```
internal/networking (calls modules/network)
   ↓ vpc_id, subnet IDs (per tier)
internal/networking (calls modules/security_groups, same internal module, second call)
   ↓ security_group_ids (ALB SG, backend SG, RDS SG)
internal/backend_edge (calls modules/alb)
   ↓ target_group_arn
internal/app_runtime (calls modules/ecs_service)
```
**Why Terraform knows this ordering, concretely**: `internal/backend_edge/main.tf` receives `vpc_id`, `alb_subnet_ids`, `alb_security_group_id` as *its own* module input variables — supplied by `application_platform/main.tf` from `module.networking`'s outputs (e.g. `module.networking.vpc_id`). Terraform's dependency graph is built from exactly these reference expressions: wherever `module.networking.xxx` appears as an argument to `module "backend_edge"`, Terraform knows `networking` must be fully applied before `backend_edge` can begin. There's no explicit `depends_on` needed for this whole chain — it's 100% implicit, driven by real data flowing between modules.

**Database chain**:
```
internal/networking (modules/network's db-tier subnet IDs + modules/security_groups' RDS SG)
   ↓ db_subnet_ids, rds_sg_id
internal/app_data (calls modules/rds)
```
Same mechanism — `internal/app_data` receives subnet/SG IDs as inputs from `application_platform/main.tf`, which sources them from `module.networking`'s outputs.

**One explicit exception, found this phase**: inside `modules/ecs_service` itself (not between top-level modules, but within the service module), `aws_ecs_service.this` has `depends_on = [aws_iam_role_policy_attachment.execution_managed]` — because the service's dependency on that IAM attachment being *fully propagated* isn't expressible as a data reference (the service doesn't consume any output of the attachment resource itself, only the role ARN, which exists before the attachment completes). This is the one place in the whole traced chain where implicit dependency isn't sufficient and the repo correctly reaches for explicit `depends_on`.
