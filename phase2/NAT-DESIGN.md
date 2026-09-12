# NAT Design — `private_app_nat_mode` Traced End to End

## The Terraform chain

```
var.private_app_nat_mode                     (variables.tf, default "required",
                                              validation: must be required|canary|disabled)
   ↓
local.nat_gateway_count                      (main.tf:20-22)
local.private_app_nat_routes                 (main.tf:27-33)
   ↓
aws_eip.nat            count = local.nat_gateway_count
aws_nat_gateway.this   count = local.nat_gateway_count
                       subnet_id = aws_subnet.public_edge[count.index]
                       depends_on = [aws_internet_gateway.this]
   ↓
aws_route.private_app_default   for_each = local.private_app_nat_routes
                                route_table_id = aws_route_table.private_app[tonumber(each.key)]
                                destination_cidr_block = "0.0.0.0/0"
                                nat_gateway_id = aws_nat_gateway.this[each.value].id
   ↓
aws_route_table_association.private_app  → aws_subnet.private_app[N]
```

## The exact locals logic (verbatim from `main.tf`)

```hcl
nat_gateway_count = var.private_app_nat_mode == "required" ? length(var.availability_zones) : (
  var.private_app_nat_mode == "canary" && length(var.availability_zones) > 0 ? 1 : 0
)

private_app_nat_routes = var.private_app_nat_mode == "required" ? {
  for idx in range(length(var.availability_zones)) : tostring(idx) => idx
  } : (
  var.private_app_nat_mode == "canary" && length(var.availability_zones) > 0 ? {
    "0" = 0
  } : {}
)
```

## ⚠️ Correction to my own Phase 1 analysis

In Phase 1's `network-module-analysis.md` I wrote that in `canary` mode *"all traffic funnels through the single NAT regardless of which AZ it originates in — meaning canary mode still has cross-AZ NAT data-transfer cost."* **That was wrong**, and reading `local.private_app_nat_routes` in full this phase disproves it.

In `canary` mode the route map is `{ "0" = 0 }` — **only `aws_route_table.private_app[0]` receives a default route.** Route table `[1]` (and any higher index) gets **no `0.0.0.0/0` route at all**. There is no cross-AZ funnelling, because there is no route for AZ-2's traffic to follow in the first place.

So `canary` actually means: **AZ-1's private app subnet has NAT egress; every other AZ has none.** The name is literal — it's a single canary route, useful for validating that a workload genuinely survives without NAT while keeping one escape hatch open. It is *not* "a cheaper shared NAT for everyone."

## Mode comparison (2 AZs)

| | `required` | `canary` | `disabled` |
|---|---|---|---|
| `aws_eip.nat` | 2 | 1 | 0 |
| `aws_nat_gateway.this` | 2 | 1 | 0 |
| `aws_route.private_app_default` | 2 (one per AZ) | **1 (AZ-1 only)** | 0 |
| AZ-1 internet egress | ✅ via its own NAT | ✅ via the single NAT | ❌ |
| AZ-2 internet egress | ✅ via its own NAT | ❌ **no default route at all** | ❌ |
| AWS service access (ECR/logs/secrets/KMS/STS/S3) | ✅ via endpoints | ✅ via endpoints | ✅ **via endpoints** |
| Cross-AZ NAT data charge | none | none (no cross-AZ route exists) | n/a |
| Cost | highest | middle | **lowest — no NAT at all** |
| Used by | `prod-app` | — | `nonprod-app` |

## The questions answered

**How many NAT Gateways per mode?** `required` = one per AZ; `canary` = exactly 1; `disabled` = 0.

**Why does NAT cost money?** Two meters: an hourly charge per gateway that runs whether or not traffic flows, plus a per-GB data-processing charge on everything passing through. The hourly charge is what makes a forgotten NAT the classic surprise-bill item — it bills at full rate on an idle learning environment.

**Why is one NAT per AZ preferred for HA?** A NAT gateway is a zonal resource. If AZ-1 fails in `required` mode, AZ-2's private subnets keep their own NAT in AZ-2 and continue reaching the internet. It also avoids cross-AZ data-transfer charges, since each AZ's egress stays within its own AZ.

**Why would a team intentionally use one NAT?** Cost, in a non-production environment where an AZ-scale outage is an acceptable risk. Note that Blueprint's `canary` is a *stricter* variant of this than the usual "single shared NAT" pattern — it doesn't give the other AZs egress at all.

**What is the failure mode of a shared NAT (or `canary`)?** In `canary`, AZ-1's NAT is a single point of failure for the only AZ that has egress — and AZ-2 never had any. If AZ-1 fails, all internet egress is gone. In a conventional shared-NAT design (where all AZs route to one NAT), an AZ-1 failure kills egress for *every* AZ, including healthy ones — the outage blast radius exceeds the failure blast radius, which is precisely the anti-pattern `required` mode exists to avoid.

**What happens if NAT is disabled?** No private subnet has any `0.0.0.0/0` route. Outbound to arbitrary internet destinations fails completely. AWS service calls still succeed **through the VPC endpoints** — this is the whole point of the endpoint set.

**How do VPC endpoints reduce NAT dependency?** They move ECR/logs/Secrets Manager/KMS/STS/S3 traffic off the public path entirely (see `VPC-ENDPOINTS.md`). Since those are exactly what a Fargate task needs to start and run, the NAT becomes optional rather than mandatory.

**What still requires NAT?** Anything not covered by an endpoint: pulling from Docker Hub / public registries, `apt`/`npm`/`pip` from public repos, third-party API calls (payment providers, webhooks), OS/package updates, and any AWS service without an interface endpoint configured (only 6 are enabled here — e.g. SQS, SNS, DynamoDB are **not** in the list, so a workload calling those in `disabled` mode would fail).

**CHEAP_MODE vs HA_MODE**: `nonprod-app` uses `disabled` (0 NAT — genuinely the cheapest, no NAT hourly charge at all); `prod-app` uses `required` (one NAT per AZ). This is the single largest cost difference between the two environments.

## Design weakness worth documenting (not fixing this phase)
`disabled` mode silently gives private subnets no egress path. If a developer adds a workload calling an AWS service *without* a corresponding interface endpoint (SQS, SNS, DynamoDB…), it fails at runtime with a connection timeout — and nothing in Terraform warns them at plan time. The `interface_endpoint_services` variable's `validation` block actually *restricts* the allowed list to the same six services, so adding a seventh requires editing the module itself. Defensible (it prevents typos) but inflexible.
