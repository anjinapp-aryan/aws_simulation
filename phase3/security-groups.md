# Security Groups — `modules/security_groups/` Traced

## What exists (verified)
Repo-wide: **9 × `aws_security_group`**, **6 × `aws_security_group_rule`**, **1 × `aws_default_security_group`**.

In `modules/security_groups/`:
| SG | Role |
|---|---|
| `aws_security_group.backend_alb` | the ALB — accepts 443 from the internet/CloudFront |
| `aws_security_group.backend_service` | ECS tasks — accepts `app_port` **from the ALB SG only** |
| `aws_security_group.rds` (named `rds-from-backend-sg`) | RDS — accepts 3306 **from the backend SG only** |

Plus separate rule resources wiring them together: `aws_security_group_rule.backend_alb_to_backend_service`, `aws_security_group_rule.backend_service_to_rds`.

## The traffic model

```
Internet / CloudFront
      │  :443
      ↓
┌──────────────────┐
│  backend_alb SG  │
└──────────────────┘
      │  :app_port (default 8080)   ← SG-to-SG reference, not CIDR
      ↓
┌────────────────────────┐
│ backend_service SG     │   ECS Fargate tasks, private_app subnets
└────────────────────────┘
      │  :3306                       ← SG-to-SG reference, not CIDR
      ↓
┌──────────────┐
│   rds SG     │   RDS, private_db subnets
└──────────────┘
```

## Why `Internet → RDS` must never be allowed
Three independent layers already prevent it, and that redundancy is the point:
1. **Routing**: `aws_route_table.private_db` has **no `0.0.0.0/0` route in any NAT mode** — there is no path, regardless of any SG rule (verified in Phase 2).
2. **Security Group**: the RDS SG's only ingress is from the backend SG — no CIDR-based rule exists.
3. **RDS setting**: `publicly_accessible = false` in `modules/rds/main.tf`.

A public database is one of the highest-severity misconfigurations in cloud security — the failure mode is "entire dataset exfiltrated by an internet-wide scanner," typically within hours. Defence in depth means an SG mistake alone cannot cause it here.

## Why `ECS-SG → RDS-SG` beats a CIDR rule

```hcl
# what Blueprint does — identity-based
source_security_group_id = aws_security_group.backend_service.id

# the weaker alternative — address-based
cidr_blocks = ["10.40.21.0/24"]
```

The SG reference is better for three concrete reasons:
1. **Survives renumbering** — change subnet CIDRs and the rule is still correct.
2. **Expresses intent** — "the backend service may reach the database" is self-documenting; `10.40.21.0/24` requires a lookup to understand.
3. **Cannot over-grant by accident** — if a *different* workload is later placed in that same subnet, a CIDR rule silently grants it database access too. An SG reference does not.

Point 3 is the one that actually bites in production. A CIDR rule grants access to *whatever happens to be at that address in future*; an SG reference grants access to *a specific identity*.

## Stateful behaviour — and why it matters here
Security Groups are **stateful**: allowing inbound 443 automatically permits the response, with no outbound rule needed. Consequences:
- You almost never need symmetric rules. Most "I added an outbound rule and it still doesn't work" confusion comes from assuming stateless behaviour.
- **Egress rules still matter**, though — `modules/network`'s `aws_security_group.interface_endpoints` declares `egress = []`, explicitly removing Terraform's default allow-all egress. That is a deliberate hardening step, and a reminder that an over-tight egress rule *can* be the blocker.
- Contrast with NACLs (stateless), where the missing ephemeral-port return rule is the classic bug. Full comparison in `../phase2/SG-VS-NACL.md`.

## `aws_default_security_group.lockdown`
```hcl
count  = var.lockdown_default_security_group ? 1 : 0   # default true
vpc_id = aws_vpc.this.id
# no ingress/egress blocks declared → all rules stripped
```
Every VPC has a default SG that allows unrestricted traffic between members of itself. Anything launched **without an explicitly specified SG** lands there. Blueprint empties it, so the fallback position for a misconfigured resource is *no connectivity* rather than *implicit trust with every other default-SG member*. Cheap, easily forgotten, genuinely valuable.

## Dynamic blocks — the optional-rule idiom
```hcl
dynamic "egress" {
  for_each = var.egress_endpoint_sg_id == null ? [] : [var.egress_endpoint_sg_id]
  ...
}
```
`for_each` over a 0-or-1-element list is how you make a nested block conditional. Used repeatedly across this repo (also in `modules/alb`'s `default_action` and `modules/ecs_service`'s `load_balancer`/`alarms` blocks) — worth recognising on sight.

## Failure modes
| Broken | Symptom | Discriminator |
|---|---|---|
| RDS SG ingress removed | app cannot reach DB | **timeout** (dropped) — not "connection refused" |
| Backend SG ingress from ALB removed | ALB targets go unhealthy → **503** | target group shows unhealthy, tasks still RUNNING |
| Endpoint SG 443 ingress removed | ECS tasks **fail to start** | startup failure, not runtime failure |
| Egress over-tightened | outbound calls hang | often overlooked because SGs are stateful |

**The universal discriminator**: *timeout = dropped by SG/NACL*; *connection refused = reached the host, nothing listening*; *AccessDenied = IAM, not network at all*.
