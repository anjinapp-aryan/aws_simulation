# `modules/network/` — Deep Trace

1. **VPC creation**: `resource "aws_vpc" "this"` — single resource, `cidr_block = var.vpc_cidr`, DNS support/hostnames both hardcoded `true`.
2. **AZ discovery**: `data "aws_availability_zones" "available" {}` exists in the file, but subnets actually use `var.availability_zones` (a variable, not this data source directly) — meaning the caller (`internal/networking`) decides the AZ list explicitly rather than the network module auto-discovering and using all of them. The data source's real purpose in this module is unclear from `main.tf` alone without checking every reference — worth a Phase 2 follow-up, don't assume it's dead code.
3. **Subnet calculation**: 3 tiers, each `count = length(var.availability_zones)`, CIDR pulled by index from `var.public_app_subnet_cidrs[count.index]` / `private_app_subnet_cidrs[count.index]` / `private_db_subnet_cidrs[count.index]` — the caller supplies pre-computed CIDR lists (not `cidrsubnet()` math inside this module), meaning CIDR planning is the *root's* responsibility, not this module's.
4. **count**: as above — index-based, tied 1:1 to AZ list position.
5. **for_each**: interface VPC endpoints — `for_each = toset(var.interface_endpoint_services)`, keyed by service name string (e.g. `"ecr.api"`, `"kms"`, `"logs"`, `"secretsmanager"`, `"sts"`).
6. **NAT control**: `local.nat_gateway_count` (see #8) drives both the EIP count (`aws_eip.nat`, `count = local.nat_gateway_count`) and the NAT gateway count itself.
7. **`private_app_nat_mode`**: a 3-valued string variable (`required`/`canary`/`disabled`), validated by `variables.tf:89`.
8. **`local.nat_gateway_count` exact logic**:
   ```
   required → length(var.availability_zones)   (1 NAT per AZ)
   canary   → length(var.availability_zones) > 0 ? 1 : 0   (single shared NAT)
   disabled → 0
   ```
9. **Route tables**: `local.private_app_nat_routes` builds a map keyed by subnet index — in `required` mode every index gets its own NAT route (1:1 AZ-to-NAT), in `canary` mode only index `"0"` gets a route (all traffic funnels through the single NAT regardless of which AZ it originates in — meaning `canary` mode still has cross-AZ NAT data-transfer cost, a real trade-off nuance not obvious from the variable name alone).
10. **Interface endpoints**: `local.interface_endpoint_actions` is a map from service name to the exact IAM actions that endpoint's policy allows (e.g. `ecr.api` → `BatchCheckLayerAvailability`/`BatchGetImage`/etc.) — this is itself a least-privilege pattern: each endpoint's resource policy is scoped to only the actions that service actually needs, not a wildcard.
11. **Why VPC endpoints at all**: with NAT `disabled`, private subnets have zero internet route — but ECS still needs to pull images (ECR), write logs (CloudWatch Logs), fetch secrets (Secrets Manager), decrypt (KMS), and assume roles (STS). Interface endpoints let those specific AWS API calls reach AWS's network without ever leaving the VPC or needing a NAT/internet path at all. This is *why* `private_app_nat_mode = "disabled"` is viable for CHEAP_MODE without breaking ECS — the endpoints substitute for NAT on exactly the calls ECS needs.
12. **1 AZ vs 2 AZ**: subnet count triples per tier (1→2, 3→6 total), NAT count changes per mode (0 either way if `disabled`; 1 either way if `canary`; 1→2 if `required`), route table complexity scales with AZ count in `required` mode only.
13. **NAT mode comparison** (verified via the exact locals logic, not guessed):

| Mode | NAT count (2 AZ) | Cross-AZ NAT data-transfer cost | Internet egress from private subnets |
|---|---|---|---|
| `disabled` | 0 | none | none — relies entirely on VPC endpoints for AWS API calls; no general internet access at all |
| `canary` | 1 | yes, for the AZ without its own NAT | yes, but single point of failure and cross-AZ cost |
| `required` | 2 (1 per AZ) | no | yes, full HA |

## Real bug found this phase (see `terraform-tests-analysis.md` for full detail)
`local.flow_logs_name_prefix` (main.tf:24) fails when `var.flow_logs_name_prefix` is null and the null-check doesn't actually short-circuit the `trimspace()` call the way the code author apparently expected. Reproduced live via `terraform test` in isolation — 0 passed, 1 failed, 11 skipped.
