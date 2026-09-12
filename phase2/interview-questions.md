# Phase 2 Interview Questions — VPC & Networking

Every answer is grounded in verified `AWS-ECS-Blueprint` evidence, not textbook definitions.

---

# VERY HIGH PRIORITY

**Q1. What is a VPC?**
A logically isolated virtual network in AWS with its own private IP range, in which you place subnets, ENIs and gateways. In our Blueprint it's `aws_vpc.this` with `cidr_block = var.vpc_cidr` (`10.40.0.0/16` nonprod, `10.30.0.0/16` prod — deliberately non-overlapping so the two could be peered later without renumbering) and DNS support/hostnames both hardcoded `true`. It's the root of the module's entire dependency graph — every other resource takes `vpc_id = aws_vpc.this.id`.

**Q2. Public vs private subnet?**
**Routing defines it, not the name.** A subnet is public if its associated route table has `0.0.0.0/0 → Internet Gateway`. In Blueprint: `aws_route_table.public_edge` has exactly that route; `aws_route_table.private_app` has at most `0.0.0.0/0 → NAT`; `aws_route_table.private_db` has **no `0.0.0.0/0` route in any mode** — making the DB tier genuinely *isolated*, not merely private. Worth adding: all three tiers set `map_public_ip_on_launch = false`, so even the "public" subnets don't auto-assign public IPs.

**Q3. How does a private subnet access the internet?**
Via a NAT Gateway in a public subnet: private route table `0.0.0.0/0 → NAT`, then the public route table `0.0.0.0/0 → IGW`. NAT holds the public IP (`aws_eip.nat`) and does many-to-one translation. It's outbound-only — it has no mechanism to initiate inbound connections.

**Q4. How does a NAT Gateway work, and why can't a private subnet just use the IGW directly?**
Two reasons. First, **it wouldn't work**: the IGW only performs 1:1 NAT for resources that already *have* a public IP. Fargate tasks here have none, so packets would leave with a private source address and replies would never return. Second, **it would be a security hole**: routing to an IGW is the definition of a public subnet, so you'd make your app tier publicly addressable with only SGs standing in the way.

**Q5. Internet Gateway vs NAT Gateway?**
IGW: VPC-level, bidirectional, free, 1:1 NAT for resources with public IPs. NAT GW: subnet-level (zonal), outbound-only, hourly + per-GB charge, many-to-one translation for resources without public IPs. In Blueprint the NAT sits *in* a public subnet and depends on the IGW — `aws_nat_gateway.this` has an explicit `depends_on = [aws_internet_gateway.this]`.

**Q6. Why one NAT per AZ?**
A NAT gateway is zonal. With one per AZ (`private_app_nat_mode = "required"`, prod), an AZ-1 failure leaves AZ-2 with its own NAT and its egress intact. With a shared NAT, an AZ-1 failure takes egress away from *healthy* AZs too — the outage blast radius exceeds the failure blast radius. It also avoids cross-AZ data-transfer charges.

**Q7. How do VPC endpoints work?**
Two kinds. **Interface endpoints** create real ENIs with private IPs in your subnets (PrivateLink), guarded by a security group, with `private_dns_enabled = true` overriding public AWS DNS names to resolve to those private IPs — so no application change is needed. **Gateway endpoints** (S3/DynamoDB only) aren't ENIs at all; they're route table entries, and they're free. Blueprint creates 6 interface endpoints (`ecr.api`, `ecr.dkr`, `logs`, `sts`, `secretsmanager`, `kms`) plus an S3 gateway endpoint.

**Q8. Security Group vs NACL?**
SG: stateful, ENI-level, allow-only, can reference other SGs. NACL: stateless, subnet-level, ordered rules, supports deny. Blueprint uses SGs extensively and **has no `aws_network_acl` resource at all** — the default allow-all NACL applies, which mirrors mainstream practice. The stateless-ness is the practical trap: a NACL needs an explicit outbound rule for the ephemeral port range or responses are silently dropped.

**Q9. How does traffic reach an ECS task?**
Internet → IGW → public route table → public subnet → ALB (SG allows 443) → then **intra-VPC via the implicit `local` route** to the task's private subnet, where the task SG must allow the app port *from the ALB's SG*. The ALB→task hop uses no route you wrote — every VPC has an unremovable `local` route for its own CIDR, which is why that hop is always a Security Group question and never a routing question.

**Q10. Why is RDS in private subnets?**
Because it only ever receives connections from inside the VPC. `aws_route_table.private_db` has no internet route in any NAT mode, so RDS is *architecturally* unreachable from the internet rather than merely firewalled — plus `modules/rds` sets `publicly_accessible = false`. Defence in depth: remove the path, then also restrict permission.

**Q11. How would you troubleshoot ECS → RDS connectivity?**
Recognise immediately that it's intra-VPC, so the `local` route always exists — routing is almost never the cause. Go straight to Security Groups: check RDS SG ingress references the backend SG, and backend SG egress permits 3306. Then discriminate by error type: **timeout = dropped by SG**; **connection refused = reached the host, nothing listening**; **auth error = credentials, not network**. Blueprint's `least_privilege.tftest.hcl` already asserts exactly one 3306 ingress rule, so if that test passes and it still fails, the RDS SG is not your problem.

**Q12. How would you troubleshoot ECS → ECR failure?**
First read the exact `stoppedReason`. **`AccessDenied` = IAM (execution role); timeout = network.** Never conflate them. If network and NAT is disabled, check: both `ecr.api` *and* `ecr.dkr` endpoints exist (you need both), the **S3 gateway endpoint** exists (ECR layers are stored in S3 — pulls fail without it even when both ECR endpoints are healthy), the endpoint SG allows 443 from the task subnet CIDR, and `private_dns_enabled` is true.

---

# HIGH PRIORITY

**Q13. Route table association — why does it matter?**
An unassociated subnet silently falls back to the VPC's **main** route table. Nothing errors; behaviour just differs from its siblings — one of the hardest network bugs to spot by reading Terraform. Blueprint prevents it structurally: `aws_route_table_association.private_app` uses `count = length(aws_subnet.private_app)`, so associations always scale with subnets.

**Q14. CIDR calculation?**
`10.40.0.0/16` = 65,536 addresses; each `/24` = 256, minus **5 AWS-reserved** (`.0` network, `.1` router, `.2` DNS, `.3` future, `.255` broadcast) = 251 usable. Blueprint's 6 subnets use 1,536 of 65,536 = 2.34%. Note Blueprint uses **hand-written CIDR lists, not `cidrsubnet()`** — explicit and auditable (matching how corporate IPAM teams actually allocate ranges), at the cost of a latent bug: add an AZ without extending all three CIDR lists and you get `Error: Invalid index`, because nothing validates the list lengths match.

**Q15. VPC DNS?**
`enable_dns_support` and `enable_dns_hostnames` are both hardcoded `true`. Critically, `private_dns_enabled = true` on the interface endpoints is what makes `secretsmanager.eu-west-1.amazonaws.com` resolve to a *private* IP. If it were false, the name would resolve publicly, and in `disabled` NAT mode there's no route to public IPs — so a **DNS** misconfiguration would present as a **timeout**, sending you hunting a routing bug.

**Q16. Interface vs Gateway endpoint?**
Interface = ENI + SG + per-hour-per-AZ cost + works for most services. Gateway = route table entry + free + **S3 and DynamoDB only**. Cost nuance worth stating: 6 interface endpoints × 2 AZs = **12 billed ENIs**, which at low traffic can cost *more* than the single NAT gateway they replace. "Endpoints are cheaper" is an oversimplification — they win on security and at high data volumes.

**Q17. NAT failure?**
Fingerprint: **"internet broken, AWS services still fine."** That asymmetry means NAT, because AWS service traffic goes via endpoints and bypasses NAT entirely. Check `describe-nat-gateways` for `failed`/`deleting` state, the EIP association, and the public subnet's IGW route.

**Q18. AZ failure — what exactly survives?**
Not "AZ-2 takes over." Concretely, in `required` mode: AZ-2's subnets, route tables, tasks, its own NAT, and its own endpoint ENI all survive; the ALB survives (multi-AZ); RDS fails over only if `multi_az = true` (prod) and is a hard outage if `false` (nonprod). In `canary` mode there's an **asymmetry**: losing AZ-1 destroys the only NAT route that exists, killing all egress; losing AZ-2 costs nothing extra.

---

# SENIOR / ARCHITECT

**Q19. How would you design networking for multi-AZ ECS?**
Three tiers × N AZs: public edge (ALB + NAT), private app (tasks), isolated DB. One shared public route table; **one private route table per AZ** (so each can point at its own zonal NAT); one DB route table with no internet route at all. Interface endpoints with an ENI in every AZ. That's exactly Blueprint's shape, and the per-AZ private route table is the detail people miss — a single shared private route table makes per-AZ NAT impossible.

**Q20. How would you minimise NAT cost?**
Add VPC endpoints for every AWS service the workload uses, then reduce NAT: per-AZ → single → none. Blueprint's `private_app_nat_mode` encodes exactly this ladder. Confirm first that nothing needs *non-AWS* internet (package installs, third-party APIs) — that's what actually forces NAT to stay.

**Q21. How would you design a VPC without NAT?**
Enumerate every outbound dependency, provide an interface endpoint for each AWS one (plus S3/DynamoDB gateway endpoints, which are free), ensure `private_dns_enabled` so no code changes, bake images with dependencies pre-installed so no package manager needs the internet, and accept that any genuine third-party call needs an alternative (a proxy in a public subnet, or an AWS-side integration). Blueprint's nonprod runs exactly this way. The gap to watch: its endpoint list is `validation`-restricted to six services, so a workload calling SQS/SNS/DynamoDB would fail with no plan-time warning.

**Q22. How would you isolate application and database tiers?**
Structurally, not just by permission: give the DB tier a route table with no internet route (so it *cannot* egress regardless of SG mistakes), place it in dedicated subnets, and use SG-to-SG references (`allow 3306 FROM sg-backend`) rather than CIDR rules so the intent survives renumbering. Blueprint does all three, and asserts the SG shape in a test.

**Q23. How would you design VPC endpoints securely?**
Scope the **endpoint policy** to only the actions needed (Blueprint's `local.interface_endpoint_actions` lists exact actions per service), restrict the endpoint SG to 443 from known CIDRs with empty egress, and add account conditions (the S3 gateway policy uses `StringEquals aws:PrincipalAccount`). Subtlety worth raising: the endpoint policy can deny an action even when IAM allows it — producing an `AccessDenied` that looks like an IAM bug and isn't.

**Q24. How would you troubleshoot intermittent cross-AZ connectivity?**
"Intermittent" usually means "affects one AZ's share of requests." Compare behaviour per-AZ rather than in aggregate: check whether each AZ's private route table has the route you assume, whether an endpoint ENI exists in every AZ, and whether one AZ's NAT is unhealthy. `canary` mode produces exactly this signature — roughly half of egress attempts fail depending on which AZ the task landed in. VPC Flow Logs filtered by subnet make the pattern obvious.

**Q25. How would you design networking across multiple AWS accounts, and when would you use Transit Gateway?**
Per-account VPCs with non-overlapping CIDRs (Blueprint's nonprod/prod split is a small-scale rehearsal of this). VPC peering is fine for a handful of VPCs but is non-transitive and becomes O(n²) connections. Transit Gateway once you have many VPCs/accounts needing any-to-any or hub-and-spoke routing, centralised egress, or on-prem connectivity — it's transitive and centrally routed, at the cost of per-attachment and per-GB charges. Out of scope for this project; worth knowing the threshold.

**Q26. How would you scale IP addressing?**
Plan tiers with room to grow — Blueprint reserves third-octet blocks of 10 per tier (public `.1-.10`, DB `.11-.20`, app `.21-.30`), so it scales to ~9 AZs per tier without collision. Beyond that: larger subnet prefixes for the app tier (Fargate consumes one ENI IP per task, so app subnets exhaust first), secondary CIDR blocks on the VPC, and central IPAM allocation to prevent future peering collisions.

---

# The Phase 2 gate questions

Answer these cold, before reading the above. Self-classify each **GREEN** (senior-level) / **YELLOW** (partial) / **RED** (revisit).

1. A private ECS task cannot reach ECR. Walk the full network path and diagnostic process.
2. A private subnet cannot reach the internet. How do you determine whether it's route table / NAT / IGW / subnet association / SG / NACL / DNS?
3. Why can NAT be disabled in some environments while ECS still reaches AWS services?
4. Why should production normally have NAT per AZ?
5. What happens when the route table is correct but the SG blocks traffic — and how do you tell that apart from a routing problem?
6. Explain VPC → subnet → route table → route → IGW/NAT/endpoint → destination, without notes.
7. Explain public vs private vs isolated subnet using *this* architecture.
8. Give your complete ECS → RDS troubleshooting tree.
9. Why do Terraform references create most dependencies automatically, and when is an explicit `depends_on` necessary? (Two real examples exist in this repo — name them.)
10. In a 2-AZ architecture, what breaks if AZ-1's NAT fails, and how should the architecture respond?
11. What makes a subnet public — and what does `map_public_ip_on_launch = false` on a "public" subnet mean?
12. Why does the DB route table have no internet route in *any* NAT mode, and why does that matter more than an SG rule?
13. What does `canary` NAT mode *actually* do to AZ-2's traffic? (Careful — the intuitive answer is wrong.)
14. Why does a missing S3 gateway endpoint break ECR image pulls?
15. If `private_dns_enabled` were false, what symptom would you see, and why would it mislead you?
16. Why do most ECS endpoint-related failures show up as *task startup* failures rather than runtime failures?
17. How many usable IPs in a `/24`, and what are the 5 reserved addresses?
18. What happens if you add an AZ but forget to extend the subnet CIDR lists?
19. Are VPC endpoints always cheaper than NAT? Justify.
20. Why is `aws_default_security_group.lockdown` worth having?
