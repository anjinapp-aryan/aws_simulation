# Phase 1 — Reuse Audit

## Candidates inspected this phase

| Repo | Archived | License | Last push | Stars | Verdict |
|---|---|---|---|---|---|
| `aws-ia/ecs-blueprints` | No | Apache-2.0 | 2026-09-09 (2 days before this audit) | 298 | REFERENCE |
| `omerbsezer/Fast-Terraform` | No | MIT | 2025-02-12 (**13+ months stale**) | 419 | SECONDARY, selective |
| `terraform-aws-modules/terraform-aws-ecs` | No | Apache-2.0 | 2026-08-09 | 676 | MODULE REFERENCE |
| `a-grivet/terraform-blueprint-ecs-standalone` | No | Apache-2.0 (verified in LICENSE file; GitHub API misreported as NOASSERTION) | 2026-05-14, 1 commit | 0 | **REFERENCE ONLY — module source is unverifiable, see finding below** |

## Critical finding: Candidate D's modules are not inspectable

`infrastructure/environments/dev/main.tf` sources every module from:
```
source = "git::ssh://your-alert-email@example.com/a-grivet/terraform-modules-aws-aws.git//modules/security-groups?ref=v1.0.0"
```
`your-alert-email@example.com` is not a real git host — this looks like an unedited template placeholder, or a private repo the public clone has no access to either way. **The actual module implementations (security_groups, alb, ecs, aurora, kms, ecr, secrets-manager) are not present anywhere in the cloned repo and cannot be verified.** Only the top-level composition (`environments/dev/main.tf`, 651 lines) is readable — it shows *which* AWS services get wired together (KMS-per-service: separate keys for RDS/Secrets/DynamoDB/Redis; Aurora + Redis with an auto-generated auth token stored in Secrets Manager; Route 53 record wired to the ALB) but not *how* any of it is actually implemented. Treat this repo as an **architecture-idea reference only** — do not adapt or reuse any of its module code, because there is no module code to inspect.

## Reuse Decision Matrix

| Capability | Existing repo | Reuse? | Adapt? | Reference only? | Why |
|---|---|:-:|:-:|:-:|---|
| Terraform fundamentals (provider/resource/variable/count/for_each syntax) | Fast-Terraform | | | ✅ | Broad syntax coverage, but 13-month-stale and lab-style (not composable) — use only to see a clean isolated example of a construct, never to copy a lab wholesale |
| ECS architecture ideas (official AWS reference) | aws-ia/ecs-blueprints | | | ✅ | Official AWS org, very active, Apache-2.0 — good to compare our own ECS module design against, but Blueprint is already our primary and more mature for our specific target shape |
| ECS module abstraction | terraform-aws-modules/terraform-aws-ecs | | | ✅ | 676-star community-standard module — useful to see what a more generic, published module's input/output surface looks like, contrasted against Blueprint's hand-rolled `modules/ecs_service` |
| Production blueprint (VPC/SG/ALB/ECS/RDS, tested, CI'd) | AWS-ECS-Blueprint | ✅ | | | Already the foundation — real modules, real `.tftest.hcl`, real CI, real cost-tier guard, verified this phase via `fmt`/`validate`/`test` |
| Terraform tests | AWS-ECS-Blueprint | ✅ | | | `least_privilege.tftest.hcl` verified real and meaningful; `vpc_defaults.tftest.hcl` verified to have a real bug (see `terraform-tests-analysis.md`) — reuse the *pattern*, be aware of the *specific bug* |
| VPC | AWS-ECS-Blueprint | ✅ | | | `modules/network` — real 3-tier subnetting, real AZ-driven `count`, verified via `terraform validate` |
| ALB | AWS-ECS-Blueprint | ✅ | | | `modules/alb` — real listener/target-group/health-check chain with deployment-circuit-breaker integration points |
| IAM | AWS-ECS-Blueprint | ✅ | | | `modules/ecs_service/iam.tf` — real task-role/execution-role split, verified |
| CI/CD | AWS-ECS-Blueprint | ✅ | | | 11 real GitHub Actions workflows incl. `deploy.yml`/`destroy.yml`/`drift-detection.yml` |
| Architecture explanation / composition ideas | aws-ia/ecs-blueprints | | | ✅ | Compare, don't copy |

## Final answer

**Reuse**: `AWS-ECS-Blueprint` wholesale, unchanged, as established in Phase 0 — nothing this phase's evidence changed that decision.
**Adapt**: nothing yet — Phase 1 is analysis-only, no adaptation performed.
**Reference/study only**: Fast-Terraform (selective, syntax examples), aws-ia/ecs-blueprints (architecture comparison), terraform-aws-modules/terraform-aws-ecs (module-design comparison), terraform-blueprint-ecs-standalone (composition ideas only — its module code is unverifiable).
**Built**: nothing. This entire phase was reading, running `fmt`/`validate`/`test` (zero AWS calls), and documenting.
