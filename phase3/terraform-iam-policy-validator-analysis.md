# `awslabs/terraform-iam-policy-validator` — Evaluation

## What it is
An AWS Labs CLI tool (`tf-policy-validator`) that parses IAM identity-based and resource-based policies out of a Terraform template/plan and runs them through **IAM Access Analyzer** checks.

| | |
|---|---|
| Repo | github.com/awslabs/terraform-iam-policy-validator |
| License | **MIT-0** ✅ |
| Stars | 355 |
| Last push | **2025-06-09** (~15 months before this audit) ⚠️ |
| Install | `pip install tf-policy-validator` (Python, Poetry-managed) |
| Invocation | `tf-policy-validator validate --config iam_check/config/default.yaml --template-path ./my-template.json --region us-east-1` |

## What problem it solves
Real IAM policy validation against AWS's own analyzer, rather than string matching. Available checks:
| Check | API call | Purpose |
|---|---|---|
| ValidatePolicy | `access-analyzer:ValidatePolicy` | policy grammar + best-practice findings |
| CheckNoNewAccess | `access-analyzer:CheckNoNewAccess` | compare against a reference policy — "does this PR widen permissions?" |
| CheckAccessNotGranted | `access-analyzer:CheckAccessNotGranted` | assert a list of critical actions is **not** granted |
| CheckNoPublicAccess | `access-analyzer:CheckNoPublicAccess` | assert a resource policy grants no public access |

`CheckAccessNotGranted` is a near-perfect fit for the identified gap: it could assert directly that the **task role does not grant `secretsmanager:GetSecretValue` / `ecr:*`**.

## ⚠️ Two disqualifying facts for *this phase*

### 1. It requires real AWS credentials and makes real API calls
The tool calls IAM Access Analyzer. The README documents the required principal permissions (`access-analyzer:ValidatePolicy`, `CheckNoNewAccess`, `CheckAccessNotGranted`, `CheckNoPublicAccess`). This is **not** a local/offline validator — it cannot run in Phase 3's zero-credential, zero-API-call constraint.

### 2. Custom policy checks cost money
Straight from the README:
> "Note that a charge is associated with each custom policy check."

`CheckNoNewAccess`, `CheckAccessNotGranted` and `CheckNoPublicAccess` are **billed per invocation**. A per-PR CI gate running these across 14 IAM roles would incur a recurring charge. `ValidatePolicy` is the free one; the checks that address our gap are the paid ones.

### 3. Staleness (secondary concern)
Last push 2025-06-09. The repo's own Terraform is pinned to 1.13.1 with AWS provider 6.x; the tool parses plan JSON, whose schema is versioned, so compatibility is **unverified**. Not disqualifying on its own, but it means adoption requires a verification step rather than a straight `pip install`.

## Comparison against the alternative

| | `tf-policy-validator` | Native `.tftest.hcl` assertion |
|---|---|---|
| Cost | **paid** per custom check | **free** |
| AWS credentials | **required** | **not required** (proven this phase) |
| Offline / CI without AWS | ❌ | ✅ |
| Depth of analysis | real Access Analyzer semantics (understands `Deny`, conditions, policy interaction) | string/structure matching on rendered JSON |
| Toolchain | Python + pip + config YAML | already in the repo's toolchain |
| Consistency with repo style | new, separate tool | identical pattern to `least_privilege.tftest.hcl` |
| Catches "is this *semantically* over-permissive?" | ✅ genuinely | ❌ only what you explicitly assert |

## Decision: **REFERENCE now — revisit at Phase 5+**

**Not rejected on quality** — it is AWS-official, MIT-0, and semantically far stronger than string matching. Rejected for *this phase* because it violates the zero-cost/zero-credential constraint, and because the gap it would close can be closed for free using a mechanism already proven to work here (see `iam-testing-gap.md`).

**Revisit when**: real AWS is in play (Phase 5+), and specifically if a CI gate on IAM changes becomes valuable. At that point `CheckAccessNotGranted` against the task role is the single highest-value check, and the per-check charge would be justified.

**What I take from it now, for free**: the *idea* of `CheckAccessNotGranted` — asserting that a specific list of critical actions is **not** granted — is directly transferable into a native test assertion. The concept is reusable even though the tool is not, in this phase.
