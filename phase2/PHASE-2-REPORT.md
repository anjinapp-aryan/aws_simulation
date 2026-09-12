# Phase 2 Report — VPC & Networking

## Executive Summary
Phase 2 studied `AWS-ECS-Blueprint/modules/network` (530 lines) in full, audited four external VPC implementations, ran all permitted zero-cost Terraform commands, and produced nine analysis documents. **Nothing was built, adapted, or modified. No AWS resources were created. No `terraform apply` was run.** The audit's strongest conclusion is a negative one: the most popular VPC module (4,064 lines) would have made this phase's learning objective *harder*, not easier.

Three concrete findings changed my prior understanding — two correcting my own earlier work.

## Repositories Audited
| Repo | Lines | License | Last push | Decision |
|---|---|---|---|---|
| `terraform-aws-modules/terraform-aws-vpc` | 4,064 | Apache-2.0 | 2026-08-28 | REFERENCE |
| `aws-ia/terraform-aws-vpc` | 1,620 | Apache-2.0 | 2026-09-07 | REFERENCE |
| `lm-academy/terraform-aws-networking-tf-course` | 141 | MIT | 2024-12 (stale) | REFERENCE (one ADAPT idea flagged) |
| `doitintl/tf-fundamentals-workshop-101` | n/a | Apache-2.0 | 2024-03 (2.5 yr stale) | DO NOT USE |
| **`AWS-ECS-Blueprint/modules/network`** | **530** | MIT | active | **REUSE, unchanged** |

## Reuse Decisions
REUSE the Blueprint network module as-is. REFERENCE the two mature modules to confirm the 3-mode NAT design is an industry-recognised pattern (`terraform-aws-modules` has equivalent `single_nat_gateway`/`one_nat_gateway_per_az` variables) and to contrast CIDR-derivation philosophies. One genuine gap identified in Blueprint — no AZ-existence validation — with the lm-academy `lifecycle { precondition }` pattern noted as the idiomatic fix, **deliberately not implemented** (analysis phase; source repo is stale). **BUILD: nothing.**

## Blueprint Networking Analysis
Complete resource inventory traced: `aws_vpc`, 3 subnet tiers (`public_edge`/`private_app`/`private_db`, each `count`-scaled by AZ), `aws_internet_gateway`, `aws_route_table` ×3 kinds, `aws_route_table_association` ×3, `aws_route.private_app_default`, `aws_eip.nat`, `aws_nat_gateway.this`, `aws_vpc_endpoint.interface` (×6, `for_each`), `aws_vpc_endpoint.s3_gateway`, `aws_security_group.interface_endpoints`, `aws_default_security_group.lockdown`, and the full VPC Flow Logs stack (`aws_flow_log` + log group + IAM role + policy, created unconditionally, 365-day retention).

## Terraform Concepts Learned (networking-specific)
`count` on AZ-indexed subnets; `for_each` on service-keyed endpoints; `local.nat_gateway_count` and `local.private_app_nat_routes` conditionals; `validation` blocks on `private_app_nat_mode` and `interface_endpoint_services`; **`lifecycle { create_before_destroy = true }` on the IGW** — this resolves the "lifecycle location unknown" item left open in Phase 1; **a second explicit `depends_on`** (`aws_nat_gateway.this` → `aws_internet_gateway.this`), which together with the ECS one found in Phase 1 gives two real examples; `[*]` splat expressions in outputs; `concat()` for endpoint route-table attachment.

## VPC Architecture / CIDR / Routing / IGW / NAT / Endpoints / DNS / SG-vs-NACL
Covered in detail in `VPC-MENTAL-MODEL.md`, `CIDR-LAB.md`, `TRAFFIC-FLOWS.md`, `NAT-DESIGN.md`, `VPC-ENDPOINTS.md`, `SG-VS-NACL.md`.

## Hands-on Experiments
Six zero-cost paper experiments completed (`experiments/README.md`): resource-count predictions per AZ/NAT combination, manual CIDR math, four packet-path traces, AZ-failure survival matrix, NAT mode comparison, and the HCL short-circuit investigation. Four real-AWS experiments specified with pre-flight checklists but **not run**.

## Production Troubleshooting
13 scenarios documented in `NETWORK-TROUBLESHOOTING.md`, each in SYMPTOM → FIRST CHECK → EVIDENCE → HYPOTHESES → ROOT CAUSE → FIX → VALIDATION form, with the fix withheld until after the reasoning. Includes the discriminators that actually resolve incidents fast: timeout-vs-connection-refused, AccessDenied-vs-timeout for IAM-vs-network, and "internet broken but AWS services fine" as the NAT fingerprint.

## What Was Actually Verified
- `terraform fmt -check -recursive` → **clean, exit 0** (re-verified this phase)
- `terraform validate` on `modules/network` → **Success**, with zero AWS credentials, confirming `validate` makes no AWS API calls
- `terraform test` on `modules/network` → **reproduced the Phase 1 failure exactly**: 0 passed, 1 failed, 11 skipped
- **Root cause of that failure, newly determined this phase** via isolated `terraform console` experiments: HCL evaluates **both** operands of `&&` before applying boolean logic, so `var.x != null && trimspace(var.x) != ""` still calls `trimspace(null)` and errors. Control test (`null != null && 1 == 1` → `false`) and alternative (`trimspace(coalesce(null,"fallback"))` → `true`) confirm. **Classification: Terraform/HCL language behaviour on v1.9.8 — not repo-specific, not environment-specific.** The idiom is simply wrong and cannot work in any version with this evaluation model.
- Complete module dependency and traffic-path tracing by direct source reading
- External repo complexity/license/maintenance metrics via GitHub API and `wc -l`

## What Was NOT Verified
- Resource-count predictions (require `terraform plan` with credentials — **not run**)
- Any actual AWS network behaviour: real routing, SG enforcement, NAT translation, endpoint connectivity, DNS resolution. All remain **REAL AWS REQUIRED** per `phase1/local-vs-real-aws.md`.
- `least_privilege.tftest.hcl` execution (read in full, not run)
- Whether `data.aws_availability_zones` in `modules/network` is referenced anywhere (still open from Phase 1)

## AWS Resources Created / Destroyed
**Created: none. Destroyed: none. AWS API calls made: none.** Only GitHub API calls (public repo metadata) and local Terraform commands were executed.

## Cost-Safety Verification
No `terraform apply`, no `terraform destroy`, no `terraform plan` against AWS. No credentials were configured or used. `terraform init` ran with `-backend=false`, preventing any backend/state interaction. Total AWS spend this phase: **$0.00**.

## Known Issues
1. **`modules/network` test failure** — root cause now proven to be the HCL `&&` evaluation model, not the test. **Not fixed, not hidden.** Any consumer of this module must pass `flow_logs_name_prefix` explicitly or the module fails at plan time.
2. **No validation that the three subnet CIDR lists match `availability_zones` in length** — adding an AZ without extending all three lists produces an unhelpful `Error: Invalid index`.
3. **No validation that supplied AZs exist in the target region** — fails at apply against AWS rather than at plan with a clear message.
4. **`interface_endpoint_services` is `validation`-locked to six services** — a workload needing SQS/SNS/DynamoDB in `disabled` NAT mode would fail at runtime with no plan-time warning.
5. **Endpoint cost nuance** — 6 endpoints × 2 AZs = 12 billed ENIs, potentially exceeding the cost of the single NAT they replace at low traffic.
6. **My own Phase 1 errors, corrected here**: `canary` mode does **not** funnel all AZs through one NAT (non-zero-index AZs get no default route at all); and the `lifecycle` block I couldn't locate in Phase 1 is on the IGW.

## Phase 3 Readiness
Phase 3 (IAM + Security Groups) has a clean handoff: `modules/security_groups` was already read in Phase 1 with its `least_privilege.tftest.hcl` analysed, and `SG-VS-NACL.md` establishes the networking context Phase 3 builds on. The IAM ground truth from `modules/ecs_service/iam.tf` (task role vs execution role) is documented from Phase 1.

**Gate not yet passed.** Per the phase rules, Phase 2 is complete only after answering the 20 gate questions in `interview-questions.md` cold, self-classified GREEN/YELLOW/RED. Questions 13 (`canary` mode's real behaviour), 14 (S3 endpoint breaking ECR pulls), and 15 (`private_dns_enabled` misleading symptom) are the ones most likely to expose gaps — all three contradict the intuitive answer.
