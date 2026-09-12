# Phase 2 Reuse Audit — VPC / Networking

## Complexity comparison (the decisive metric for a *learning* project)

| Implementation | Root `.tf` lines | Readable end-to-end in one sitting? |
|---|---|---|
| `AWS-ECS-Blueprint/modules/network` (**our baseline**) | **530** | Yes — done this phase, every resource traced |
| `terraform-aws-modules/terraform-aws-vpc` | **4,064** | No |
| `aws-ia/terraform-aws-vpc` | **1,620** | Barely |
| `lm-academy/terraform-aws-networking-tf-course` | **141** | Yes, but far too thin for our architecture |
| `doitintl/tf-fundamentals-workshop-101` | (no root `.tf`; nested per-lab modules) | N/A |

This single table drives most of the decisions below. A 4,064-line module is a **consumption** artifact (you set variables and trust it); a 530-line module is a **learning** artifact (you read it and understand every line). Our project's stated goal is understanding, not maximum abstraction.

---

## Candidate 1 — `terraform-aws-modules/terraform-aws-vpc`
- **Purpose**: the de-facto community-standard AWS VPC module.
- **License**: Apache-2.0 ✅
- **Maintenance**: excellent — 3,261 stars, last push 2026-08-28, 17 open issues.
- **Relevant features**: everything — IPv6, DHCP option sets, VPN gateways, multiple NAT strategies (`single_nat_gateway`/`one_nat_gateway_per_az`), flow logs, all endpoint types.
- **Tests/examples**: extensive `examples/` directory.
- **What we could reuse**: nothing wholesale.
- **What we should NOT reuse**: the module itself, as a replacement for `modules/network`.
- **Compatibility with Blueprint**: would require rewriting `internal/networking` and every consumer of `modules/network`'s outputs — a large, disruptive change delivering no new capability we actually need.
- **Decision: REFERENCE**
- **Reason**: It is objectively a better *general-purpose* module and worse *learning* material. Its NAT-strategy variables (`single_nat_gateway`, `one_nat_gateway_per_az`) are a useful **cross-check** that Blueprint's 3-mode `private_app_nat_mode` is an industry-recognised pattern rather than an invention — that validation is the real value here, not the code.

## Candidate 2 — `aws-ia/terraform-aws-vpc`
- **Purpose**: AWS's own (aws-ia org) VPC module.
- **License**: Apache-2.0 ✅
- **Maintenance**: very active — last push 2026-09-07 (4 days before this audit), 113 stars, 16 open issues.
- **Relevant features**: subnet-type-driven design (you declare subnet *roles*, it derives CIDRs), strong Transit Gateway / multi-account orientation.
- **What we could reuse**: nothing wholesale.
- **Compatibility**: same disruption problem as Candidate 1, plus a design philosophy (auto-derived CIDRs) that actively **hides** the CIDR math this phase is explicitly trying to teach.
- **Decision: REFERENCE**
- **Reason**: Its auto-CIDR-derivation is a genuine convenience in production and a genuine *handicap* for learning — `CIDR-LAB.md` exists precisely to do that math by hand.

## Candidate 3 — `lm-academy/terraform-aws-networking-tf-course`
- **License**: MIT ✅
- **Maintenance**: ⚠️ stale — last push 2024-12-22 (~21 months before this audit). Not archived, but not active.
- **Relevant features**: a 141-line teaching VPC with two genuinely interesting design differences from Blueprint:
  1. **`for_each` over a `subnet_config` map** instead of Blueprint's `count` over an AZ list — a direct, readable illustration of the count-vs-for_each trade-off taught in Phase 1.
  2. **`lifecycle { precondition { ... } }`** validating that the supplied AZ actually exists in the target region, with a helpful multi-line error listing the valid AZs.
- **Decision: REFERENCE (with one ADAPT candidate flagged for a later phase)**
- **Reason**: The `precondition` pattern is a real gap in Blueprint — Blueprint validates `private_app_nat_mode` values and `interface_endpoint_services` names, but **nothing validates that `availability_zones` contains real AZs for the target region**. Supplying `["eu-west-1a","eu-west-1z"]` would fail at apply time against AWS rather than at plan time with a clear message. Documented as a possible future improvement; **not implemented this phase** (Phase 2 is analysis; also the repo is stale so the idea is adopted, never the code).

## Candidate 4 — `doitintl/tf-fundamentals-workshop-101`
- **License**: Apache-2.0 ✅
- **Maintenance**: ⚠️ **2.5 years stale** — last push 2024-03-07, only 2 stars.
- **Relevant features**: a nested `modules/global/network/vpc` plus SG modules, workshop-structured.
- **Decision: DO NOT USE**
- **Reason**: Stale, tiny, and offers nothing the four stronger candidates plus Blueprint don't already cover. Adding it would be dependency noise.

---

## Final Phase 2 reuse decision

| Need | Decision | Source |
|---|---|---|
| VPC/subnet/route/IGW/NAT/endpoint implementation | **REUSE, unchanged** | `AWS-ECS-Blueprint/modules/network` |
| Confidence that the 3-mode NAT design is industry-standard | **REFERENCE** | `terraform-aws-modules/terraform-aws-vpc`'s equivalent NAT variables |
| CIDR-derivation design alternatives | **REFERENCE** | `aws-ia/terraform-aws-vpc` |
| AZ-existence `precondition` validation idea | **REFERENCE now, possible ADAPT later** | `lm-academy` course module |
| Anything else | **BUILD NOTHING** | — |

**Nothing was built, adapted, or replaced this phase.** The Blueprint network module satisfies every Phase 2 learning objective, and the audit's strongest finding is a *negative* one: the most popular module (4,064 lines) would have made this phase's learning objective harder, not easier.
