# Security Groups vs NACLs

## The core division of responsibility

```
Route table answers:      "Is there a PATH to the destination?"
Security Group answers:   "Is this traffic ALLOWED?"
```
Both must say yes. A perfect route table with a blocking SG looks identical, from the client's perspective, to a missing route — which is exactly why network troubleshooting needs a deterministic order of checks (see `NETWORK-TROUBLESHOOTING.md`).

## Comparison

| | Security Group | Network ACL |
|---|---|---|
| Attaches to | ENI (instance/task/endpoint level) | Subnet |
| Stateful? | **Yes** — return traffic is automatically allowed | **No** — you must explicitly allow the return path |
| Rule types | **Allow only** | Allow **and Deny** |
| Evaluation | All rules evaluated; any match = allow | Rules evaluated **in numbered order**, first match wins |
| Default (new, custom) | Deny all inbound, allow all outbound | Default NACL: allow all both ways; custom NACL: deny all both ways |
| Can reference other SGs? | **Yes** — the key feature | No, CIDR only |
| Typical production use | The primary control, does ~all the work | Left at default; used only for coarse subnet-wide denies (e.g. blocking a known-bad CIDR) |

## What the Blueprint actually does

**Security Groups: used extensively.**
- `modules/network`: `aws_security_group.interface_endpoints` (443 from private app CIDRs, `egress = []`)
- `modules/security_groups`: `backend_alb`, `backend_service`, `rds` plus SG-to-SG rules (`backend_alb_to_backend_service`, `backend_service_to_rds`), with `least_privilege.tftest.hcl` asserting exact ingress-rule counts

**NACLs: not used at all.** There is **no `aws_network_acl` resource anywhere in the repo** (verified). The VPC's default NACL — allow-all in both directions — therefore applies to every subnet. This matches mainstream production practice and is a deliberate choice, not an omission.

**Related but distinct**: `aws_default_security_group.lockdown` (`count = var.lockdown_default_security_group ? 1 : 0`, default `true`) strips **all rules** from the VPC's default security group. This is important and often missed: anything launched into the VPC without an explicitly specified SG lands in the default SG. Left untouched, the default SG allows all traffic between members of itself — so an accidentally-misconfigured resource could talk to others. Blueprint empties it, so the fallback position is "no connectivity" rather than "implicit trust."

## Why the SG-to-SG reference pattern matters
```
RDS SG: allow 3306 FROM sg-backend-service     ← identity-based
RDS SG: allow 3306 FROM 10.40.21.0/24          ← address-based
```
The first stays correct when subnets are renumbered, and expresses *intent* ("the backend service may reach the database") rather than an implementation detail. The second silently becomes wrong — or silently over-permissive — if another workload is later placed in that CIDR. Blueprint uses SG-to-SG references for the app tiers, which is the stronger pattern.

## Why stateless-ness makes NACLs painful
A stateful SG that allows inbound 443 automatically permits the response. A stateless NACL requires an inbound rule for 443 **and** an outbound rule for the ephemeral port range (1024–65535) that the client used. Forgetting the ephemeral-port return rule is the single most common NACL bug — connections hang rather than fail fast, because the request arrives and the response is silently dropped.

## When you would actually reach for a NACL
- Blocking a specific malicious CIDR across an entire subnet, where adding a deny to every SG would be error-prone (SGs cannot express deny at all).
- A compliance requirement for a second, independent enforcement layer.
- A coarse blast-radius control, e.g. guaranteeing a database subnet can never talk to the internet *even if* someone misconfigures an SG.

For this architecture, the third case is already handled structurally — `aws_route_table.private_db` has no internet route at all, so there's nothing for a NACL to add.

## Interview-critical summary
> SGs are stateful, ENI-level, allow-only, and can reference other SGs — they do the real work. NACLs are stateless, subnet-level, ordered, and support deny — they're a coarse secondary layer most teams leave at default. If traffic is being blocked and your SGs look correct, check whether a NACL is dropping the *return* path, since a stateless rule set makes asymmetric failures possible in a way SGs never do.
