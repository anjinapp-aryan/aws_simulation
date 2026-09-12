# Phase 2 Experiments

**Status: all experiments below are PAPER experiments (zero AWS cost, zero resources created).**
Experiments requiring real AWS are specified but deliberately **not executed** — Phase 2's gate must be passed first, and no `terraform apply` is permitted.

---

## Experiment 1 — Resource-count prediction (ZERO COST, completed)

**Method**: derive expected resource counts by hand from the module source, before ever running `terraform plan`.

### The counting model (derived from `modules/network/main.tf`)
```
FIXED (independent of AZ count and NAT mode) = 11
  aws_vpc                        1
  aws_internet_gateway           1
  aws_route_table.public_edge    1
  aws_route_table.private_db     1
  aws_vpc_endpoint.s3_gateway    1
  aws_security_group.interface_endpoints  1
  aws_default_security_group.lockdown     1   (var defaults true)
  aws_flow_log.vpc               1
  aws_cloudwatch_log_group.vpc_flow_logs  1
  aws_iam_role.vpc_flow_logs     1
  aws_iam_role_policy.vpc_flow_logs       1

INTERFACE ENDPOINTS = 6            (default list: ecr.api, ecr.dkr, logs, sts, secretsmanager, kms)

PER-AZ (×N) = 7N
  aws_subnet.public_edge                  N
  aws_subnet.private_app                  N
  aws_subnet.private_db                   N
  aws_route_table_association.public_edge N
  aws_route_table.private_app             N
  aws_route_table_association.private_app N
  aws_route_table_association.private_db  N

NAT = 2 × nat_gateway_count        (aws_eip.nat + aws_nat_gateway.this)

DEFAULT ROUTES (aws_route.private_app_default):
  required → N     canary → 1     disabled → 0
```

### Predictions
| Config | Fixed | Endpoints | 7N | NAT×2 | Routes | **Total** |
|---|---|---|---|---|---|---|
| 1 AZ, `disabled` | 11 | 6 | 7 | 0 | 0 | **24** |
| 2 AZ, `disabled` (**= nonprod actual**) | 11 | 6 | 14 | 0 | 0 | **31** |
| 2 AZ, `canary` | 11 | 6 | 14 | 2 | 1 | **34** |
| 2 AZ, `required` (**= prod actual**) | 11 | 6 | 14 | 4 | 2 | **37** |
| 3 AZ, `required` | 11 | 6 | 21 | 6 | 3 | **47** |

**Verification status: UNVERIFIED.** Confirming these requires `terraform plan` against a real AWS account (plan creates nothing but needs credentials). Deferred — the *reasoning* is the learning objective; the count is a check on it.

**Caveat on exactness**: these counts cover `modules/network` in isolation. A real `nonprod-app` plan includes every other module (ALB, ECS, RDS, S3, CloudFront, governance…) and will be far larger. Do not expect 31.

---

## Experiment 2 — CIDR math by hand (ZERO COST, completed)
See `../CIDR-LAB.md`. Worked `10.40.0.0/16` → 6 × /24 subnets, 251 usable IPs each, 2.34% VPC utilisation, and derived the 3-AZ extension following the module's own numbering convention.

---

## Experiment 3 — Packet-path tracing (ZERO COST, completed)
See `../TRAFFIC-FLOWS.md`. Four flows traced hop-by-hop to named Terraform resources: Internet→ALB→ECS, ECS→RDS, ECS→AWS-service (NAT path vs endpoint path vs S3 gateway path), private→internet.

---

## Experiment 4 — AZ-failure analysis (ZERO COST, completed)
See `../NETWORK-TROUBLESHOOTING.md` Scenario 7. Produced the per-mode survival matrix and the non-obvious finding that `canary` mode's failure impact is **asymmetric by AZ** — losing AZ-1 destroys all egress, losing AZ-2 costs nothing.

---

## Experiment 5 — NAT mode comparison (ZERO COST, completed)
See `../NAT-DESIGN.md`. Produced the mode table and **corrected a Phase 1 error**: `canary` does not funnel all AZs through one NAT; non-zero-index AZs get no default route at all.

---

## Experiment 6 — HCL short-circuit investigation (ZERO COST, completed, REAL RESULT)

**Question**: is the known `modules/network` test failure caused by repo code, Terraform behaviour, or the local environment?

**Method**: isolated `terraform console` tests in a scratch directory (no AWS, no project files touched).

| Test | Expression | Result |
|---|---|---|
| 1 | `null != null && trimspace(null) != ""` | **ERROR**: `Invalid value for "str" parameter: argument must not be null` |
| 2 (control) | `null != null && 1 == 1` | `false` — evaluates fine |
| 3 (alternative) | `trimspace(coalesce(null, "fallback")) != ""` | `true` — works |

**Conclusion**: HCL evaluates **both operands** of `&&` before applying boolean logic. A false left operand does **not** prevent the right operand's function call from being evaluated and erroring. Therefore `var.x != null && trimspace(var.x) != ""` is **not a valid null-guard in Terraform** — it cannot work in any version with this evaluation model.

**Classification**: **Terraform/HCL language behaviour** (verified on Terraform v1.9.8) — *not* repo-specific, *not* environment-specific. The Blueprint's idiom is genuinely incorrect; Test 3 shows the idiomatic fix (`coalesce`).

**Action taken: NONE.** Documented only, per the phase rule not to silently fix or hide the failing test.

---

## Experiments requiring real AWS — SPECIFIED BUT NOT RUN

These are written up so they're ready to execute after the Phase 2 gate, with explicit cost notes.

### Experiment A — Deploy networking-only, 2 AZ, NAT disabled
**Cost profile**: VPC/subnets/route tables/IGW = **free**. 12 interface-endpoint ENIs = **hourly charge (the dominant cost)**. Flow Logs = ingestion + storage. No NAT, no ALB, no ECS, no RDS.
**Pre-flight checklist**: verify account, region, root directory, `private_app_nat_mode = "disabled"`, plan reviewed resource-by-resource, no ALB/ECS/RDS/Route53/KMS/Secrets/WAF in plan, destroy time pre-committed.
**Verification**: `describe-vpcs`, `describe-subnets` (confirm AZ spread), `describe-route-tables` (confirm no `0.0.0.0/0` anywhere private), `describe-vpc-endpoints`.
**Not run.**

### Experiment B — Flip `disabled` → `canary`, observe the diff
**Expected plan diff**: +1 `aws_eip`, +1 `aws_nat_gateway`, +1 `aws_route` — **and critically, a route for AZ-1 only**, which is the prediction most worth verifying since it contradicts my own Phase 1 write-up.
**Not run.**

### Experiment C — Break a route, diagnose, fix, validate
Remove the `0.0.0.0/0` route from one private route table; confirm the symptom matches Scenario 1; restore via Terraform; confirm recovery in Flow Logs.
**Not run.**

### Experiment D — Break an endpoint SG rule, diagnose, fix
Remove 443 ingress from the endpoint SG; expect ECS task startup failure (not a runtime failure) per `VPC-ENDPOINTS.md`; restore.
**Not run** — requires ECS, which is Phase 5.
