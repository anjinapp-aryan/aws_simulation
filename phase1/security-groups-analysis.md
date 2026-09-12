# `modules/security_groups/` — Deep Trace

## Structure (from `main.tf`, verified)
Three security groups: `aws_security_group.backend_alb`, `aws_security_group.backend_service`, `aws_security_group.rds` (named `rds-from-backend-sg` in tests, confirming its ingress is scoped to the backend service specifically, not open). Plus `aws_security_group_rule` cross-references (e.g. `backend_alb_to_backend_service`, `backend_service_to_rds`) wiring SG-to-SG trust rather than CIDR-based rules — this is the real "least privilege" mechanism: an ingress rule that says "allow traffic from security group X" is tighter and self-documenting compared to "allow traffic from 10.0.0.0/16," because it stays correct even if subnet CIDRs change later.

## Dynamic blocks (verified, `main.tf:55,66`)
```hcl
dynamic "egress" {
  for_each = var.egress_endpoint_sg_id == null ? [] : [var.egress_endpoint_sg_id]
  ...
}
dynamic "egress" {
  for_each = var.egress_s3_prefix_list_id == null ? [] : [var.egress_s3_prefix_list_id]
  ...
}
```
Both are the "optional single nested block" idiom — an egress rule only gets created if the corresponding variable is non-null, letting the module skip rules for resources that don't exist in a given deployment mode (e.g. no S3 gateway endpoint egress rule if that endpoint wasn't provisioned).

## `tests/least_privilege.tftest.hcl` — verified real, read in full

| Test | What it asserts | Why it matters |
|---|---|---|
| `rds_ingress_restricted_to_backend_only` | exactly **one** TCP ingress rule on port 3306 | not "at least one" — catches an accidental second/wildcard rule that would widen DB access |
| `backend_service_ingress_from_alb_only` | exactly one TCP ingress rule on the app port (default 8080) | same pattern — ECS tasks reachable only from the ALB's SG, nothing else |
| `alb_ingress_on_listener_port` | exactly one TCP ingress rule on port 443 | the public entry point is exactly as wide as intended, no more |
| `custom_app_port_propagates` | changing `app_port` to 3000 correctly updates the backend SG ingress AND the ALB→backend egress rule, while the backend→RDS egress rule **stays hardcoded at 3306 regardless** | proves the module doesn't accidentally couple unrelated ports — RDS's port is a property of RDS, not of whatever app port the backend happens to use |
| `environment_suffix_applied` | SG names get a `-staging` suffix when `enable_environment_suffix=true` | naming-convention correctness, prevents cross-environment SG name collisions in a shared account |

## Why testing least privilege as code beats documenting it
A human reviewer reading a 200-line PR diff can miss a second `ingress {}` block, especially if it's added in a separate commit weeks later by someone who didn't read the original design doc. A test that asserts "exactly one ingress rule on port 3306" fails immediately and loudly the moment that invariant is violated, in CI, before merge — it doesn't rely on anyone remembering the original intent. This is the general principle: **security properties that matter should be assertions in code, not sentences in a README**, because assertions get enforced automatically and documentation doesn't.
