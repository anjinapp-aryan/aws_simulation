# CHEAP (nonprod) vs HA (prod) — Verified via `diff` of both `terraform.tfvars.example` files

| Variable | nonprod | prod | Effect |
|---|---|---|---|
| `private_app_nat_mode` | `"disabled"` | `"required"` | 0 NAT gateways vs 1-per-AZ — biggest single cost differentiator (see `network-module-analysis.md` for exact `local.nat_gateway_count` logic) |
| `enable_cost_optimized_dev_tier` | `true` | `false`, and **cannot** be `true` here — enforced by a `terraform validate`-time check in `internal/platform_core/main.tf:88` | Right-sizes compute/storage throughout the platform module |
| `rds_instance_class` | `db.t4g.micro` | `db.t4g.small` | Smallest vs one-tier-up instance |
| `rds_multi_az` | `false` | `true` | Single-AZ vs synchronous standby |
| `enable_managed_waf` | `false` (explicit comment: "keep WAF off unless you want the higher-protection profile") | not disabled (defaults on) | Recurring WAF cost avoided in nonprod |
| `enable_aws_backup` | `false` | not disabled | Backup vaulting cost/complexity |
| `enable_security_baseline`, `enable_account_security_controls`, `enable_aws_config` | all `false` | all `true` | **Not primarily a cost decision** — the tfvars comment explains nonprod disables these to avoid a *second* AWS Config recorder fighting with prod's, in a single-AWS-account setup. A real operational (not financial) reason for a "cheap-looking" flag. |
| commented-out budget alert thresholds | 150/50/30/60 (total/CloudFront/VPC/RDS, USD/month) | 500/150/100/200 | Even the alarm *thresholds* differ — nonprod expects to alert at much lower spend |
| `vpc_cidr` / subnet CIDRs | `10.40.0.0/16` | `10.30.0.0/16` | Different address ranges — allows both environments to coexist in the same account/region without CIDR collision if ever peered |

## How one module set produces two different infrastructures purely from variable values
Every difference above is a variable value, not a code fork — `modules/network`, `modules/rds`, `modules/ecs_service` etc. are byte-identical between `nonprod-app` and `prod-app`; only `terraform.tfvars` differs. This is the practical demonstration of "one Terraform codebase, multiple modes" from the Phase-0 design principle — and it's not a proposal, it's how this repo already actually works, verified by this diff.

## The one genuinely interesting non-cost finding
The `enable_security_baseline`/`enable_aws_config` split reveals a constraint that isn't about money at all: **AWS Config only allows one account-wide recorder**, so if both `nonprod-app` and `prod-app` tried to enable it simultaneously in the same AWS account, they'd conflict. This is the kind of real operational gotcha that only surfaces from reading two tfvars files side by side — not something a single-environment tutorial would ever teach.
