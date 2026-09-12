# Local vs Real AWS — Classification

| Concept | Classification | Evidence |
|---|---|---|
| Terraform syntax (provider/resource/variable/output/locals/count/for_each/dynamic/conditional) | **LOCAL** | `terraform fmt -check` and `terraform validate` both ran this phase with zero AWS credentials, zero network calls to AWS |
| Module dependency graph | **LOCAL** | Entirely derivable by reading `source =` references — no AWS interaction needed, done this phase |
| Terraform test (`.tftest.hcl`) | **LOCAL** | `mock_provider` fakes all AWS responses; verified this phase — ran, found a real bug, zero AWS touched |
| `terraform plan` | **LOCAL execution, but requires real AWS read access** | Makes real read-only API calls (describe/list) to diff against actual state — creates nothing, but is not credential-free like `validate`/`test`/`fmt` |
| VPC/subnet/SG resource graph shape | **PARTIAL** | Ministack (per earlier phase's empirical probe) gets AZ assignment and CIDR math correct — proves Terraform HCL is *structurally* sound, but doesn't prove real network enforcement |
| Security Group actual traffic enforcement | **REAL AWS REQUIRED** | Not tested this phase (Phase 1 forbids `apply`); flagged from the earlier Ministack probe as unverifiable locally |
| ALB health check / actual routing | **REAL AWS REQUIRED** | Earlier phase's Ministack probe: `elbv2 create-load-balancer` returned a syntactically valid but unreachable fake DNS name |
| ECS container actually running | **REAL AWS REQUIRED** | Earlier phase's Ministack probe: `ecs run-task` reported `RUNNING` with zero real container spawned (`docker ps` confirmed) |
| RDS actual engine connectivity | **REAL AWS REQUIRED** | Earlier phase's Ministack probe: fake `Endpoint.Address: "localhost"` |
| IAM policy enforcement (vs syntax validity) | **REAL AWS REQUIRED** | `terraform validate` catches malformed policy JSON, but never proves an actual AssumeRole/API call would succeed or fail as intended |
| CloudWatch metrics from real infrastructure | **REAL AWS REQUIRED** | Nothing real exists locally to emit metrics from |
| Remote state (S3) + locking (DynamoDB) *mechanics* | **PARTIAL** | The DynamoDB conditional-write locking mechanism itself is real when tested against Ministack's DynamoDB (verified real in an earlier phase's connectivity-test work); but the *backend configuration itself* (`backend.tf`) has never been exercised against either Ministack or real AWS this phase |

This table is a refinement of the Phase-0 version, not a contradiction — every "REAL AWS REQUIRED" row here still traces to the same empirical Ministack probe from two phases ago, re-cited rather than re-derived, since nothing this phase's read-only Terraform work could add new evidence to that specific question (no AWS calls were made this phase at all beyond local `validate`/`test`).
