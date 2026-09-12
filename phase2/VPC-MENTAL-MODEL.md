# VPC Mental Model — Grounded in `AWS-ECS-Blueprint/modules/network`

Every entry below cites the actual resource in the 530-line module, read in full this phase.

## VPC
**What**: a logically isolated slice of AWS's network, with its own private IP space.
**Why**: without it, your ECS tasks and RDS would have no private address space and no network boundary to enforce.
**Where in our architecture**: `resource "aws_vpc" "this"` — `cidr_block = var.vpc_cidr`, `enable_dns_support`/`enable_dns_hostnames` both hardcoded `true`.
**If it fails/is misconfigured**: nothing else exists — every other resource in the module takes `vpc_id = aws_vpc.this.id`, so the VPC is the root of the entire dependency graph.

## CIDR
**What**: the IP range notation (`10.40.0.0/16`) defining how many addresses exist and which.
**Why**: subnets are carved from it; get it wrong and you either run out of IPs or collide with another network you later need to peer with.
**Where**: `var.vpc_cidr` (nonprod `10.40.0.0/16`, prod `10.30.0.0/16` — deliberately non-overlapping, see `CIDR-LAB.md`).
**If it fails**: too-small CIDR = ECS tasks fail to launch with "insufficient IP addresses"; overlapping CIDR = peering/VPN becomes impossible without renumbering.

## Availability Zone
**What**: a physically separate datacentre (or cluster of them) within a region, with independent power/cooling/network.
**Why**: the unit of failure isolation in AWS — the entire point of Multi-AZ.
**Where**: `var.availability_zones` (a list), consumed as `availability_zone = var.availability_zones[count.index]` on all three subnet tiers.
**If one fails**: see `multi-az` analysis in `NAT-DESIGN.md` and `NETWORK-TROUBLESHOOTING.md` Scenario 7.

## Subnet
**What**: a slice of the VPC CIDR bound to exactly one AZ.
**Why**: it's where ENIs (and therefore ECS tasks, RDS instances, ALB nodes, NAT gateways, VPC endpoints) actually live.
**Where**: three tiers, each `count = length(var.availability_zones)`:
- `aws_subnet.public_edge` — Tier tag `public-edge` — hosts ALB + NAT gateways
- `aws_subnet.private_app` — Tier tag `private-app` — hosts ECS tasks + interface endpoint ENIs
- `aws_subnet.private_db` — Tier tag `private-db` — hosts RDS
**Notable**: **all three tiers set `map_public_ip_on_launch = false`, including the public ones.** A "public" subnet here does not auto-assign public IPs — the ALB gets its public addressing from the ELB service, not from subnet auto-assignment.

## Route Table / Route
**What**: the rules deciding where traffic leaving a subnet goes. A route = destination CIDR → target.
**Why**: **this is what actually makes a subnet public or private** — not its name or tag.
**Where**:
- `aws_route_table.public_edge` — ONE table shared by all public subnets, with an inline `route { cidr_block = "0.0.0.0/0", gateway_id = aws_internet_gateway.this.id }`
- `aws_route_table.private_app` — `count = length(var.availability_zones)`, one **per AZ** (because each AZ may point at a different NAT)
- `aws_route_table.private_db` — ONE table shared by all DB subnets, **with no `0.0.0.0/0` route at any time, in any NAT mode**

## Route Table Association
**What**: the binding of a subnet to a route table.
**Why**: an unassociated subnet silently falls back to the VPC's *main* route table — a classic production bug (traffic works for some subnets and not others, with no obvious cause).
**Where**: `aws_route_table_association.public_edge` / `.private_app` / `.private_db`, each `count`-matched to its subnet tier.

## Internet Gateway
**What**: the VPC's door to the public internet; also performs 1:1 NAT for public IPs.
**Why**: without it there is no internet path in or out at all.
**Where**: `aws_internet_gateway.this`, with **`lifecycle { create_before_destroy = true }`** (this is the `lifecycle` block flagged as "unconfirmed" in Phase 1 — now confirmed, it's on the IGW, not RDS).
**If it fails**: public subnets lose internet; NAT gateways (which sit in public subnets and route via IGW) lose their upstream, so private subnets lose internet too.

## NAT Gateway + Elastic IP
**What**: managed outbound-only address translation, letting private subnets reach the internet without being reachable from it.
**Where**: `aws_nat_gateway.this` (`count = local.nat_gateway_count`), each placed in `aws_subnet.public_edge[count.index]`, each with an `aws_eip.nat[count.index]`, and **`depends_on = [aws_internet_gateway.this]`** (a second explicit `depends_on` in this repo — the NAT genuinely needs the IGW attached first, with no data reference to express that).
**Full detail**: `NAT-DESIGN.md`.

## Public / Private / Isolated Subnet
Defined **by routing**, not by name:
- **Public** = route table has `0.0.0.0/0 → IGW`. Our `public_edge` tier.
- **Private** = no IGW route; may have `0.0.0.0/0 → NAT`. Our `private_app` tier (in `required`/`canary` mode).
- **Isolated** = no `0.0.0.0/0` route at all, ever. **Our `private_db` tier is genuinely isolated** — `aws_route_table.private_db` is created with no internet route in any mode. RDS can never reach or be reached from the internet, by construction, independent of any NAT setting.

## VPC Endpoint — Interface vs Gateway
- **Interface endpoint** (`aws_vpc_endpoint.interface`, `for_each = toset(var.interface_endpoint_services)`): creates real **ENIs with private IPs inside your subnets** (`subnet_ids = aws_subnet.private_app[*].id` — one per AZ, so it's AZ-resilient by default). Guarded by `aws_security_group.interface_endpoints`. Costs per-hour-per-ENI plus data processing.
- **Gateway endpoint** (`aws_vpc_endpoint.s3_gateway`): **not an ENI** — it's a *route table entry*. Attached via `route_table_ids = concat(aws_route_table.private_app[*].id, [aws_route_table.private_db.id])`. **Free.** Only S3 and DynamoDB support this type.
**Full detail**: `VPC-ENDPOINTS.md`.

## DNS support / DNS hostnames
**Where**: both hardcoded `true` on `aws_vpc.this`; `private_dns_enabled = true` on every interface endpoint.
**Why it matters critically here**: `private_dns_enabled` is what makes `ecr.eu-west-1.amazonaws.com` resolve to the endpoint's *private* IP instead of its public one. Without it, your ECS task would resolve the public address and try to route out via NAT/IGW — which, in `disabled` NAT mode, means the call simply fails. **Private DNS is the invisible glue that makes NAT-less operation work without any application code change.**

## Security Group
**What**: stateful, ENI-level allow-only firewall.
**Where (this module)**: `aws_security_group.interface_endpoints` — allows 443 ingress from `var.private_app_subnet_cidrs`, and notably declares **`egress = []`** (explicitly empty, removing the default allow-all egress).
**Division of labour**: routing decides *"is there a path?"*; the SG decides *"is this traffic permitted?"* Both must say yes. Full contrast in `SG-VS-NACL.md`.

## NACL
**What**: stateless, subnet-level allow **and deny** rules.
**Where**: **not used by this module at all** — no `aws_network_acl` resource exists. The VPC's default NACL (allow-all both ways) therefore applies. This mirrors mainstream production practice: SGs do the work, NACLs stay default unless you have a specific coarse deny requirement.
**Related**: `aws_default_security_group.lockdown` (`count = var.lockdown_default_security_group ? 1 : 0`, default `true`) strips all rules from the VPC's *default security group* — a distinct hardening step from NACLs, ensuring anything accidentally launched without an explicit SG gets zero connectivity.

## VPC Flow Logs (present, and a cost item worth knowing)
`aws_flow_log.vpc` + `aws_cloudwatch_log_group.vpc_flow_logs` + IAM role/policy — **created unconditionally** (no `count`), `traffic_type = "ALL"`, `max_aggregation_interval = 60`, and `var.flow_logs_retention_days` defaults to **365**. This is the module's main non-obvious recurring cost, and simultaneously the single most valuable artifact for network troubleshooting (see `NETWORK-TROUBLESHOOTING.md`).
