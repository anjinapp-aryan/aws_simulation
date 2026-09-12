# `modules/alb/` — Resource Chain (verified from actual `main.tf`)

```
Internet
   ↓
aws_lb.this                          (internal = var.internal, subnets = var.alb_subnet_ids,
                                       security_groups = [var.alb_security_group_id],
                                       drop_invalid_header_fields = true,
                                       access_logs { bucket = var.access_logs_bucket, enabled = true })
   ↓
aws_lb_listener.https                (port = var.alb_listener_port, protocol = HTTPS,
                                       certificate_arn = var.certificate_arn)
   ↓  (one of two mutually-exclusive dynamic default_action blocks)
   ├─→ forward to aws_lb_target_group.backend        (when enable_origin_auth_header = false)
   └─→ fixed-response 403 "Forbidden"                 (when enable_origin_auth_header = true —
                                                        blocks direct ALB access, forcing traffic
                                                        through CloudFront's origin-auth header instead)
   ↓
aws_lb_target_group.backend          (port = var.app_port, protocol = HTTP — plaintext INSIDE
                                       the VPC; TLS is only terminated at the ALB/CloudFront edge,
                                       explicitly flagged with a checkov:skip comment explaining why
                                       this is intentional, not an oversight)
   health_check {
     path = var.health_check_path, matcher = var.health_check_matcher,
     healthy_threshold, unhealthy_threshold, interval, timeout — all variables, not hardcoded
   }
   ↓
[ECS service registers tasks into this target group — see ecs-analysis.md]
   ↓
Container (port = var.app_port, must match the target group's port exactly)
```

## Listener rules for origin authentication (real, found this phase — not in my Phase-0 read)
`aws_lb_listener_rule.origin_auth_primary` and `origin_auth_secondary` (priority 10/11) only forward traffic when a specific HTTP header (`origin_auth_header_name`/`value`) is present — this is how the Blueprint prevents someone from bypassing CloudFront and hitting the ALB directly: CloudFront is configured to inject a secret header on every request it forwards, and the ALB only forwards traffic carrying that header (checked via `count = var.enable_origin_auth_header && trimspace(var.origin_auth_header_value) != "" ? 1 : 0`). The "primary"/"secondary" pair supports header *rotation* without downtime — old and new secret values both accepted during a rotation window.

## Every link, Terraform-resource-to-resource
| Link | Terraform mechanism |
|---|---|
| ALB → subnets | `aws_lb.this.subnets = var.alb_subnet_ids`, sourced from `internal/networking`'s network module output |
| ALB → security group | `security_groups = [var.alb_security_group_id]`, sourced from `internal/networking`'s security_groups module output |
| Listener → ALB | `load_balancer_arn = aws_lb.this.arn` — implicit dependency via direct reference |
| Listener → target group | `target_group_arn = aws_lb_target_group.backend.arn` inside the dynamic `default_action` — implicit dependency |
| Target group → VPC | `vpc_id = var.vpc_id` |
| ECS service → target group | `load_balancer_target_group_arn` passed as a module variable from `internal/backend_edge`'s ALB module output into `internal/app_runtime`'s ECS module call (traced in `nonprod-module-dependency.md`) |

## Direct relevance to "ALB returns 503" (analysis only, no troubleshooting performed this phase)
Three independent Terraform-configured reasons a 503 can occur even with the infrastructure correctly deployed:
1. Target group `health_check` thresholds (`healthy_threshold`/`unhealthy_threshold`/`interval`) — a task that's actually fine can still show unhealthy if the check path/timeout is misconfigured relative to the app's real startup time.
2. `deployment_circuit_breaker` (see `ecs-analysis.md`) can trigger an automatic rollback mid-deploy, leaving a transient window with fewer healthy targets than desired count.
3. The `origin_auth_header` listener rule: if CloudFront's header injection breaks or someone hits the ALB directly, the *default* action might be the 403 fixed-response, not a 503 — but if the header check itself is misconfigured (wrong header name/value), that's a Terraform-config-driven traffic-drop mechanism a troubleshooter must know exists.
