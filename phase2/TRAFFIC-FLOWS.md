# Traffic Flows — Traced Through Actual Blueprint Resources

## Flow A — Internet → ALB → ECS task

```
Internet client
  ↓ DNS resolves ALB name → ALB public IPs
Internet Gateway              aws_internet_gateway.this
  ↓ (VPC has an IGW attached; IGW does 1:1 NAT for the ALB's public IPs)
Public route table            aws_route_table.public_edge  →  0.0.0.0/0 → igw
  ↓ (associated to public subnets via aws_route_table_association.public_edge)
Public subnet                 aws_subnet.public_edge[N]     (Tier = public-edge)
  ↓ ALB SG must allow :443 ingress  ← modules/security_groups: aws_security_group.backend_alb
ALB                           (modules/alb — Phase 4 territory, referenced only)
  ↓ ALB → target: this is VPC-LOCAL traffic, uses the implicit `local` route, NOT the IGW
  ↓ ECS task SG must allow app_port ingress FROM the ALB's SG (SG-to-SG reference)
Private app subnet            aws_subnet.private_app[N]     (Tier = private-app)
  ↓
ECS task ENI → container
```

**Key insight**: the ALB→ECS hop never touches a route table entry you wrote. Every VPC has an implicit `local` route covering the whole VPC CIDR, which cannot be removed or overridden. So ALB→ECS is *always* routable; whether it's *permitted* is 100% a Security Group question. This is the single most common source of "the route table looks fine, why is it broken" confusion.

**Why ECS is reachable from the ALB but not the internet**: the ECS task sits in `private_app`, whose route table (`aws_route_table.private_app[N]`) has **no IGW route in any mode**. Inbound internet traffic has no return path and no entry path. The IGW existing at the VPC level does not expose it.

---

## Flow B — ECS → RDS

```
ECS task in private_app subnet
  ↓ destination 10.40.11.x (private_db CIDR) matches the implicit `local` route
  ↓ NO NAT, NO IGW, NO endpoint involved — pure intra-VPC routing
  ↓ RDS SG must allow :3306 FROM the ECS task's SG
       ← modules/security_groups: aws_security_group.rds,
         verified by least_privilege.tftest.hcl to have EXACTLY ONE 3306 ingress rule
Private DB subnet             aws_subnet.private_db[N]      (Tier = private-db)
  ↓
RDS instance ENI
```

**Why RDS does not need to be public**: it only ever receives connections from inside the VPC. `aws_route_table.private_db` is created **with no `0.0.0.0/0` route whatsoever, in any NAT mode** — verified by reading the resource; it has only the implicit `local` route plus the S3 gateway endpoint association. RDS is therefore *architecturally* unreachable from the internet, not merely firewalled from it. `modules/rds` additionally sets `publicly_accessible = false`.

**Where security is actually enforced**: entirely at the SG layer. Routing permits any intra-VPC flow; the RDS SG is the only thing stopping, say, a compromised ALB from talking to the database directly.

---

## Flow C — ECS → AWS service (two competing paths)

### Path C1 — via NAT (the "internet" path)
```
ECS task (private_app)
  ↓ resolves e.g. secretsmanager.eu-west-1.amazonaws.com → PUBLIC IP
  ↓ private_app route table: 0.0.0.0/0 → NAT   (only exists in required/canary mode)
NAT Gateway (in a public subnet)     aws_nat_gateway.this[N]
  ↓ public route table: 0.0.0.0/0 → IGW
Internet Gateway
  ↓
AWS service public endpoint
```
Costs: NAT hourly + NAT data processing + the traffic leaves and re-enters AWS's edge.

### Path C2 — via Interface Endpoint (the private path)
```
ECS task (private_app)
  ↓ resolves secretsmanager.eu-west-1.amazonaws.com → PRIVATE IP
     ← because private_dns_enabled = true on aws_vpc_endpoint.interface
  ↓ destination is now inside the VPC CIDR → implicit `local` route
  ↓ endpoint SG must allow :443 from private_app CIDRs
     ← aws_security_group.interface_endpoints (ingress 443 from var.private_app_subnet_cidrs)
Interface endpoint ENI in aws_subnet.private_app[N]
  ↓ (AWS PrivateLink backbone)
AWS service
```
**Never touches NAT, IGW, or the public internet.**

### Path C3 — S3 only, via Gateway Endpoint
```
ECS task (private_app)
  ↓ private_app route table has a prefix-list route for S3 → vpce
     ← aws_vpc_endpoint.s3_gateway, attached via route_table_ids
S3
```
Gateway endpoints are route-table entries, not ENIs — **free**, no SG involved.

**Why the Blueprint can disable NAT entirely**: the six interface endpoints (`ecr.api`, `ecr.dkr`, `logs`, `sts`, `secretsmanager`, `kms`) plus the S3 gateway endpoint cover every AWS dependency a Fargate task has at startup and runtime. With `private_app_nat_mode = "disabled"` (the nonprod default), path C1 ceases to exist, C2/C3 still work, and ECS runs normally. What *stops* working is any call to a **non-AWS** internet destination — see `NAT-DESIGN.md`.

---

## Flow D — Private subnet → arbitrary internet

```
ECS task (private_app)
  ↓ 0.0.0.0/0 → nat_gateway_id      aws_route.private_app_default
NAT Gateway in aws_subnet.public_edge[N]
  ↓ 0.0.0.0/0 → igw                 aws_route_table.public_edge
Internet Gateway
  ↓
Internet
```

**Why a private subnet cannot just route directly to the IGW**: it technically *could* — adding `0.0.0.0/0 → igw` to the private route table is syntactically valid. But it wouldn't work, and it would be a security hole:
1. **It wouldn't work**: the IGW performs 1:1 NAT only for instances that *have a public IP*. ECS Fargate tasks in this architecture have none (`assign_public_ip` is false, and `map_public_ip_on_launch = false` on every subnet). With no public IP, the IGW has nothing to translate to — packets leave with a private source address and replies never return.
2. **It would be a security hole**: routing to an IGW is the literal definition of a public subnet. Adding that route would make the ECS subnet publicly addressable, and only SGs would stand between your tasks and the internet.

NAT solves both: it holds the public IP (the `aws_eip.nat`), performs many-to-one translation, and is **outbound-only** — it has no mechanism to initiate inbound connections.
