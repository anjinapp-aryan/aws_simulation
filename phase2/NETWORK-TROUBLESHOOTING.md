# Network Troubleshooting Playbook

Every scenario follows: **SYMPTOM → FIRST CHECK → EVIDENCE → HYPOTHESES → ROOT CAUSE → FIX → VALIDATION**.
Diagnostic reasoning comes before the fix, deliberately.

## The universal first-principles order
Work the path in this order every time; it eliminates whole categories fastest:
```
1. Is there a PATH?        → subnet → route table association → route → target
2. Is it PERMITTED?        → Security Group (source egress + destination ingress) → NACL
3. Does the NAME resolve?  → DNS / private_dns_enabled / endpoint present
4. Is the IDENTITY valid?  → IAM (this is NOT a network problem — don't conflate)
```

---

## Scenario 1 — Private subnet cannot reach the internet
**SYMPTOM**: ECS task times out calling a third-party API (e.g. `api.stripe.com`).
**FIRST CHECK**: which NAT mode is this environment in? `grep private_app_nat_mode <root>/terraform.tfvars`
**EVIDENCE**:
```bash
aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=<subnet>" \
  --query 'RouteTables[].Routes[]'
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=<vpc>" --query 'NatGateways[].[NatGatewayId,State]'
```
**HYPOTHESES**: (a) `disabled` mode — no `0.0.0.0/0` route by design; (b) `canary` mode and this task is in AZ-2, which has no route; (c) NAT exists but is in a failed state; (d) SG egress blocks it; (e) route table not associated to this subnet.
**ROOT CAUSE (most likely here)**: nonprod runs `private_app_nat_mode = "disabled"` — **there is no internet egress at all, by design**. Third-party API calls cannot work in nonprod as configured.
**FIX**: either set `private_app_nat_mode = "canary"`/`"required"` (accepting NAT cost), or remove the external dependency, or route it through an AWS service that has an endpoint.
**VALIDATION**: `describe-route-tables` shows `0.0.0.0/0 → nat-xxxx`; from the task, the call succeeds; VPC Flow Logs show ACCEPT records to the destination.

---

## Scenario 2 — ECS cannot reach ECR (`CannotPullContainerError`)
**SYMPTOM**: Task stuck in PENDING then STOPPED; `stoppedReason` mentions `CannotPullContainerError`.
**FIRST CHECK**: NAT mode. If `disabled`, this is an endpoint problem, not a NAT problem.
**EVIDENCE**:
```bash
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=<vpc>" \
  --query 'VpcEndpoints[].[ServiceName,VpcEndpointType,State]'
aws ecs describe-tasks --cluster <c> --tasks <t> --query 'tasks[].stoppedReason'
```
**HYPOTHESES**: (a) missing `ecr.api` **or** `ecr.dkr` — you need **both**; (b) **missing S3 gateway endpoint** — ECR layers live in S3, so pulls fail even with both ECR endpoints healthy; (c) endpoint SG doesn't allow 443 from the task's subnet CIDR; (d) `private_dns_enabled = false` so the task resolves ECR's public IP and has no route to it; (e) **not a network problem at all** — the *execution role* lacks ECR permissions.
**ROOT CAUSE — how to tell (b) from (e)**: an IAM failure returns an explicit `AccessDenied`/authorization error; a network failure returns a **timeout or connection refused**. Different error text, completely different fix. Never guess between them — read the exact `stoppedReason` string.
**FIX**: depends on which hypothesis the evidence supports; for (b), confirm `aws_vpc_endpoint.s3_gateway`'s `route_table_ids` actually includes this subnet's route table.
**VALIDATION**: task reaches RUNNING; endpoint `State = available`; Flow Logs show ACCEPT to the endpoint ENI IPs.

---

## Scenario 3 — ECS cannot write CloudWatch logs
**SYMPTOM**: Task **fails to start** (not "logs are missing").
**KEY INSIGHT**: with `logDriver = "awslogs"` (set in `modules/ecs_service/locals.tf`), the container **cannot start** if the log destination is unreachable. "No logs" and "task won't start" are the same root cause here.
**EVIDENCE**: is the `logs` interface endpoint present and `available`? Does `aws_cloudwatch_log_group.this` exist (Terraform creates it — if someone deleted it manually, startup fails)?
**HYPOTHESES**: missing/unhealthy `logs` endpoint; endpoint SG blocking 443; log group deleted out-of-band; execution role missing `logs:CreateLogStream`/`PutLogEvents` (IAM, not network).
**VALIDATION**: task RUNNING and log streams appearing in the expected group.

---

## Scenario 4 — ECS cannot reach Secrets Manager
**SYMPTOM**: `ResourceInitializationError` at startup.
**KEY INSIGHT**: task-definition `secrets` are resolved by the **ECS agent using the EXECUTION role** before the container starts — not by your application at runtime with the task role. A common wrong turn is granting the *task* role secret access and wondering why nothing changed.
**HYPOTHESES**: missing `secretsmanager` endpoint; **missing `kms` endpoint** (the secret is KMS-encrypted — decryption is a separate service call); endpoint SG; execution-role IAM.
**VALIDATION**: task starts; secret value present in the container environment.

---

## Scenario 5 — ECS cannot reach RDS
**SYMPTOM**: application connection timeout to the DB endpoint.
**FIRST CHECK**: this is **intra-VPC** traffic — the implicit `local` route always exists and cannot be removed. So it is almost never a routing problem. Go **straight to Security Groups**.
**EVIDENCE**:
```bash
aws ec2 describe-security-groups --group-ids <rds-sg> --query 'SecurityGroups[].IpPermissions'
aws rds describe-db-instances --db-instance-identifier <id> \
  --query 'DBInstances[].[DBSubnetGroup.Subnets[].SubnetIdentifier,PubliclyAccessible,DBInstanceStatus]'
```
**HYPOTHESES**: (a) RDS SG ingress doesn't reference the backend SG; (b) backend SG egress doesn't permit 3306; (c) RDS in a different VPC entirely; (d) DB not in `available` state; (e) app using the wrong port/hostname; (f) connection-pool exhaustion masquerading as a network timeout.
**ROOT CAUSE pattern**: timeouts point to SG; "connection refused" points to the DB not listening / wrong port; authentication errors point to credentials, not network.
**VALIDATION**: `least_privilege.tftest.hcl` already asserts exactly one 3306 ingress rule — if that test passes and connectivity still fails, the problem is *not* the RDS SG.

---

## Scenario 6 — ALB cannot reach ECS (networking aspects only; full ALB work is Phase 4)
**SYMPTOM**: target group shows targets `unhealthy`.
**NETWORK-SCOPED CHECKS**: are ALB subnets (`public_edge`) and task subnets (`private_app`) in the **same AZs**? Does the task SG allow the app port **from the ALB's SG**? Does the target group port match `container_port`?
**KEY INSIGHT**: ALB→task is intra-VPC (`local` route), so this is an SG/port/health-check question, never a route table question.
**Deferred to Phase 4**: health-check path/matcher tuning, deregistration delay, circuit-breaker interaction.

---

## Scenario 7 — One AZ loses connectivity
**SYMPTOM**: ~50% of requests failing in a 2-AZ setup.
**What survives, by mode** (derived from the actual Terraform, not assumed):
| Component | AZ-1 fails, `required` | AZ-1 fails, `canary` | AZ-1 fails, `disabled` |
|---|---|---|---|
| AZ-2 subnets/route tables | survive | survive | survive |
| AZ-2 ECS tasks | survive | survive | survive |
| AZ-2 internet egress | ✅ own NAT in AZ-2 | ❌ never had a route | ❌ by design |
| AZ-2 AWS service access | ✅ AZ-2 endpoint ENI | ✅ AZ-2 endpoint ENI | ✅ AZ-2 endpoint ENI |
| ALB | survives (multi-AZ) | survives | survives |
| RDS | fails over if `multi_az = true` (prod); **outage if `false`** (nonprod) | same | same |
**Non-obvious conclusion**: in `canary` mode, losing **AZ-1 specifically** destroys all internet egress everywhere, while losing AZ-2 costs nothing extra. The failure impact is asymmetric by AZ — an unusual property worth knowing before relying on `canary`.

---

## Scenario 8 — NAT Gateway unavailable
**SYMPTOM**: sudden loss of outbound internet from private subnets; AWS service calls unaffected.
**THE DIAGNOSTIC SIGNAL**: *"internet broken, AWS services fine"* almost always means NAT, because AWS service traffic goes via endpoints and bypasses NAT entirely. That asymmetry is the fingerprint.
**EVIDENCE**: `aws ec2 describe-nat-gateways --query 'NatGateways[].[NatGatewayId,State,SubnetId]'` — look for `failed`/`deleting`.
**HYPOTHESES**: NAT deleted/failed; its EIP released; the public subnet hosting it lost its IGW route; AZ failure.

---

## Scenario 9 — Wrong route table association
**SYMPTOM**: one subnet behaves differently from its identical-looking siblings.
**KEY INSIGHT**: an unassociated subnet silently uses the VPC's **main** route table. Nothing errors; behaviour just differs — one of the hardest network bugs to spot by reading Terraform alone.
**EVIDENCE**: `aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=<subnet>"` — if it returns the main route table, the association is missing.
**In Blueprint**: `aws_route_table_association.private_app` uses `count = length(aws_subnet.private_app)`, so associations and subnets scale together — this bug is structurally prevented here, but it's the first thing to check in unfamiliar infrastructure.

---

## Scenario 10 — Wrong subnet (task launched in the wrong tier)
**SYMPTOM**: a task has unexpected internet access, or unexpectedly lacks it.
**EVIDENCE**: `aws ecs describe-tasks ... --query 'tasks[].attachments[].details'` → compare the subnet ID against the `Tier` tags (`public-edge`/`private-app`/`private-db`).
**Why it matters**: launching into `private_db` means no NAT route *and* the DB route table — the task would fail to pull its image even in `required` mode.

---

## Scenario 11 — Security Group blocks traffic
**SYMPTOM**: timeout with a correct-looking route table.
**DISCRIMINATOR**: **timeout = dropped (SG/NACL)**; **connection refused = reached the host, nothing listening**. This single distinction resolves most "is it network or is it the app?" arguments.
**EVIDENCE**: check **both** sides — source SG egress and destination SG ingress. Blueprint's `egress = []` on the endpoint SG is a reminder that egress rules are real and can be the blocker.

---

## Scenario 12 — DNS resolution failure
**SYMPTOM**: "name or service not known", or traffic going to a public IP when you expected a private one.
**EVIDENCE**: check `enable_dns_support`/`enable_dns_hostnames` on the VPC (both hardcoded `true` in Blueprint) and `private_dns_enabled` on the interface endpoints (also `true`).
**KEY INSIGHT**: if `private_dns_enabled` were `false`, `secretsmanager.eu-west-1.amazonaws.com` would resolve to a **public** IP. In `disabled` NAT mode there's no route to public IPs — so the symptom would present as a *timeout*, and you'd waste time hunting a routing bug when the real cause is DNS resolving to the wrong address family of endpoint.

---

## Scenario 13 — VPC endpoint unavailable
**SYMPTOM**: AWS service calls fail while general internet (if NAT is on) works — the mirror image of Scenario 8.
**EVIDENCE**: `describe-vpc-endpoints` → `State`; check the endpoint ENI exists in **this task's AZ**; check the endpoint policy isn't denying the action.
**Subtle cause**: the endpoint **policy** (from `local.interface_endpoint_actions`) permits only a specific action list. An SDK call needing an action outside that list gets `AccessDenied` **from the endpoint, not from IAM** — so the IAM policy looks perfect and the call still fails. Checking only IAM would never find it.

---

## The one tool that resolves most of these fastest
**VPC Flow Logs** — created unconditionally by `modules/network` (`traffic_type = "ALL"`, 60s aggregation, 365-day retention). ACCEPT/REJECT records per flow tell you definitively whether traffic *arrived and was dropped* (security problem) versus *never arrived at all* (routing/DNS problem) — collapsing the search space before you touch a single SG rule.
