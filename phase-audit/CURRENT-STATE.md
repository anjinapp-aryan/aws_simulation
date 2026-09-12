# Current-State Matrix — Verified, Not Assumed

Method: filesystem inventory (`find`, excluding vendored `candidates/`), git status, and direct re-reading of what each phase actually produced. A Markdown file describing a capability is not counted as the capability.

## Pre-phase application layer (built before Phase 1, outside the phaseN/ structure)

| Capability | Exists? | Runnable? | $0? | Real AWS required? | Breakable? | Observable? | Fix/Recovery? | Source | Status |
|---|---|---|---|---|---|---|---|---|---|
| S3 read/write | Yes | Yes | Yes | No (Ministack) | — | **Yes — verified live** | — | `connectivity-test/` | **A. REAL HANDS-ON NOW** |
| DynamoDB CRUD | Yes | Yes | Yes | No (Ministack) | — | **Yes — verified live** | — | `connectivity-test/`, `serverless-api/` | **A** |
| SNS→SQS fan-out | Yes | Yes | Yes | No (Ministack) | — | **Yes — verified live** | — | `connectivity-test/`, `event-pipeline/` | **A** |
| SQS DLQ redrive on poison message | Yes | Yes | Yes | No (Ministack) | **Yes — actually broken (malformed event)** | **Yes — watched 3 retries then DLQ land** | **Yes — reprocessed, confirmed** | `event-pipeline/` | **A — full BUILD→BREAK→OBSERVE→FIX cycle already done** |
| Kinesis put/get | Yes | Yes | Yes | No (Ministack) | — | **Yes — verified live** | — | `connectivity-test/` | **A** |
| Presigned S3 upload URL | Yes | Yes | Yes | No (Ministack) | — | **Yes — verified live** | — | `serverless-api/` | **A** |
| Terraform apply (Ministack-targeted) | Yes | Yes | Yes | No | — | Yes | — | `terraform/`, `*/terraform/` | **A** |

**This layer is the strongest hands-on asset in the entire project.** It has already executed the exact loop the user is now asking for (BUILD→RUN→BREAK→OBSERVE→TROUBLESHOOT→FIX→VERIFY) — on the DLQ scenario specifically. It predates Phase 1 and the phaseN/ work never built on it.

## Phase 1 — Terraform + Blueprint deep learning

| Capability | Exists? | Runnable? | $0? | Real AWS required? | Breakable? | Observable? | Fix/Recovery? | Source | Status |
|---|---|---|---|---|---|---|---|---|---|
| VPC/ECS/ALB/RDS Terraform | Yes (vendored) | Yes (`validate`/`fmt`/`test` only) | Yes | Yes, for real deploy | No — never applied | No — never applied | No | `candidates/AWS-ECS-Blueprint/` | **C. STATIC LEARNING ONLY** |
| Module dependency understanding | Documented | N/A (analysis, not code) | Yes | — | — | — | — | `phase1/*.md` | **C** |
| Any script/test/Docker artifact authored by us | **None found** | — | — | — | — | — | — | — | **D. PLANNED, NOT IMPLEMENTED** |

Filesystem fact: `phase1/` contains **12 Markdown files, zero `.tf`, `.sh`, `.py`, or Dockerfiles.**

## Phase 2 — VPC & Networking

| Capability | Exists? | Runnable? | $0? | Real AWS required? | Breakable? | Observable? | Fix/Recovery? | Source | Status |
|---|---|---|---|---|---|---|---|---|---|
| VPC/subnet/routing Terraform | Yes (vendored) | `validate`/`test` only | Yes | Yes for real behavior | No | No | No | `candidates/.../modules/network` | **C** |
| HCL `&&` short-circuit experiment | Yes | **Yes — actually run** | Yes | No | N/A (language test, not infra) | **Yes — real console output observed** | N/A | scratch dir (not committed) | **A, but trivially scoped** — the one genuine build-run-observe moment in Phase 2, and it's a language experiment, not an AWS behavior |
| CIDR math, traffic-flow tracing, NAT-mode comparison | Documented | No | — | — | No | No | No | `phase2/*.md` | **C** |
| Real routing/SG/NAT/endpoint behavior | Never touched | — | — | **Yes — Ministack proven fake for this** | No | No | No | — | **E. REQUIRES REAL AWS, not attempted** |

Filesystem fact: `phase2/` contains **10 Markdown files + `experiments/README.md` describing 6 "paper experiments"** (explicitly labeled not-run in that file itself) **and 4 real-AWS experiments explicitly specified but not executed.**

## Phase 3 — IAM & Security Groups

| Capability | Exists? | Runnable? | $0? | Real AWS required? | Breakable? | Observable? | Fix/Recovery? | Source | Status |
|---|---|---|---|---|---|---|---|---|---|
| Full Blueprint test suite | Yes | **Yes — actually run, 82/0** | Yes | No | — | Yes | — | `candidates/AWS-ECS-Blueprint/modules/*` | **B. LOCAL SIMULATION** (plan-time only, no real resource) |
| IAM role-boundary test (new) | Yes | **Yes — authored, run, broken, fixed, reverted** | Yes | No | **Yes — real injected violation, real detected failure** | **Yes — exact error message observed** | **Yes — reverted, reconfirmed clean** | `candidates/.../ecs_service/tests/iam_role_boundary.tftest.hcl` | **A, scoped to policy JSON** — genuine BUILD→RUN→BREAK→OBSERVE→FIX→VERIFY, but the "system" being tested is a rendered JSON string, not running infrastructure |
| Execution role vs task role at runtime | Documented only | No | — | **Yes** | No | No | No | `phase3/*.md` | **D/E** — the entire practical point of the role split (startup failure vs runtime `AccessDenied`) has never been observed, only reasoned about |
| Workshop lab 2/4 scripts | Reviewed, not adapted, not run | No | — | Yes (need ECS/RDS) | No | No | No | `candidates/sample-devops-agent-ecs-workshop/labs/` | **D** |

Filesystem fact: `phase3/` contains **10 Markdown files + exactly one real artifact**, and that artifact lives inside the vendored `candidates/` clone, not in a `phase3/` subfolder — i.e. it is not part of the deliverable structure the roadmap specified.

## Summary counts (verified via `find`, not estimated)

| | Markdown files | Runnable non-Markdown artifacts we authored | Real AWS resources ever created | Failures actually injected against running infra |
|---|---|---|---|---|
| Pre-phase app layer | 3 READMEs | 3 Spring apps + 3 Terraform roots (all runnable) | 0 (Ministack) | **1** (DLQ poison message) |
| Phase 1 | 12 | 0 | 0 | 0 |
| Phase 2 | 11 | 0 (1 scratch experiment, uncommitted) | 0 | 0 |
| Phase 3 | 10 | 1 (`.tftest.hcl`) | 0 | **1** (IAM boundary violation, Terraform-plan scope only) |
| **phaseN/ total** | **33** | **1** | **0** | **1 (plan-scope, not runtime)** |
