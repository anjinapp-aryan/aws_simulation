# VPC Endpoints — Why Each One Exists

## What the Blueprint actually creates

```hcl
variable "interface_endpoint_services" {
  default = ["ecr.api", "ecr.dkr", "logs", "sts", "secretsmanager", "kms"]
  validation { ... }   # restricts the list to exactly these six
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = toset(var.interface_endpoint_services)
  service_name        = "com.amazonaws.${region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_app[*].id      # one ENI per AZ
  security_group_ids  = [aws_security_group.interface_endpoints.id]
  private_dns_enabled = true
  policy              = data.aws_iam_policy_document.interface_endpoint[each.key].json
}

resource "aws_vpc_endpoint" "s3_gateway" {
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(aws_route_table.private_app[*].id, [aws_route_table.private_db.id])
  policy            = data.aws_iam_policy_document.s3_gateway_endpoint.json
}
```

## Per-endpoint breakdown

| Service | Type | Why ECS needs it | NAT required without it? | Failure behaviour |
|---|---|---|---|---|
| `ecr.api` | Interface | ECR control plane — `GetAuthorizationToken`, `DescribeRepositories`, `BatchCheckLayerAvailability`. The auth step before any pull. | Yes | Task can't authenticate to ECR → stuck in PENDING, `CannotPullContainerError` |
| `ecr.dkr` | Interface | ECR Docker registry data plane — the actual image manifest/layer pull. | Yes | Same symptom; **both ECR endpoints are needed, having only one fails** |
| *S3 (gateway)* | **Gateway** | **ECR image layers are physically stored in S3.** Without S3 access the pull fails even with both ECR endpoints present. | Yes | `CannotPullContainerError` despite ECR endpoints looking healthy — a classic, confusing failure |
| `logs` | Interface | The `awslogs` log driver ships container stdout/stderr to CloudWatch Logs (`modules/ecs_service/locals.tf` sets `logDriver = "awslogs"`). | Yes | **Task fails to START.** The awslogs driver can't buffer indefinitely — if it can't reach CloudWatch, container startup fails. Not "logs are missing" — the task doesn't run. |
| `secretsmanager` | Interface | Task definition `secrets` blocks are resolved **by the ECS agent at startup**, using the *execution* role. | Yes | Task fails to start, `ResourceInitializationError` |
| `kms` | Interface | Decrypting Secrets Manager values and KMS-encrypted CloudWatch log groups (`aws_cloudwatch_log_group.vpc_flow_logs` has `kms_key_id`). | Yes | Secret retrieval fails → task fails to start |
| `sts` | Interface | `AssumeRole` — how the task obtains credentials for its task role. | Yes | Task can't get credentials; app-level AWS SDK calls fail |

**The pattern**: five of these seven failures happen **at task startup, not at runtime**. That's why an ECS task in a NAT-less subnet with a broken endpoint typically never reaches RUNNING at all, rather than starting and then misbehaving — an important diagnostic signal.

## Interface vs Gateway vs NAT

| | Interface Endpoint | Gateway Endpoint | NAT Gateway |
|---|---|---|---|
| Mechanism | ENI with a private IP in your subnet (AWS PrivateLink) | An entry in a route table | Managed many-to-one address translation |
| Attached via | `subnet_ids` | `route_table_ids` | a route + placement in a public subnet |
| Security control | Security Group + endpoint policy | endpoint policy + route table | SGs/NACLs of the source |
| Supported services | Most AWS services | **S3 and DynamoDB only** | Everything (it's just internet) |
| DNS | `private_dns_enabled` overrides public DNS to private IPs | Uses prefix lists, no DNS change | Normal public DNS |
| Cost | **Per-hour per-ENI, per-AZ, plus per-GB** | **Free** | Per-hour plus per-GB |
| Traffic leaves VPC? | No | No | Yes (to the public internet) |

**Cost nuance that matters**: with 6 interface endpoints × 2 AZs = **12 ENIs**, each billed hourly. In a low-traffic learning environment, 12 endpoint-ENI-hours can genuinely **cost more than the single NAT gateway they replace**. Endpoints win on security and on high-volume data-processing charges; they do not automatically win on raw cost at small scale. Worth stating plainly because "endpoints are the cheap option" is a common oversimplification.

## Security properties

**Endpoint policies**: each interface endpoint gets a scoped policy from `local.interface_endpoint_actions` — e.g. `ecr.api` allows only the six ECR read actions, `kms` only decrypt/describe/encrypt/generate-data-key operations. Combined with a `StringEquals: aws:PrincipalAccount = <this account>` condition on the S3 gateway policy, this means the endpoint itself refuses cross-account use — defence in depth beyond IAM.

**Endpoint SG**: `aws_security_group.interface_endpoints` allows **443 ingress from `var.private_app_subnet_cidrs` only**, and declares **`egress = []`** (explicitly empty — removing Terraform's default allow-all egress). A tight, deliberate SG.

**Note on the SG design**: ingress is CIDR-based rather than SG-reference-based. SG-to-SG references (used elsewhere in `modules/security_groups`) would be marginally tighter, since they survive CIDR changes and scope to identity rather than address. Minor, defensible — endpoints serve the whole subnet by design.

## AZ resilience
`subnet_ids = aws_subnet.private_app[*].id` places an ENI in **every** private app subnet, so each AZ has a local endpoint ENI. If AZ-1 fails, AZ-2's tasks reach AZ-2's endpoint ENI. Endpoints are therefore **more AZ-resilient by default than `canary`-mode NAT** — a genuinely interesting asymmetry: the cheap networking path (endpoints) is *more* highly available than the mid-tier NAT option.
