# CIDR Lab — Manual Math vs Blueprint Implementation

## The actual Blueprint values (from `nonprod-app/terraform.tfvars.example`)

```hcl
vpc_cidr                 = "10.40.0.0/16"
availability_zones       = ["eu-west-1a", "eu-west-1b"]
public_app_subnet_cidrs  = ["10.40.1.0/24",  "10.40.2.0/24"]
private_db_subnet_cidrs  = ["10.40.11.0/24", "10.40.12.0/24"]
private_app_subnet_cidrs = ["10.40.21.0/24", "10.40.22.0/24"]
```
Prod is identical in shape with `10.30.0.0/16`.

**Key implementation finding**: the Blueprint does **not** use `cidrsubnet()` or `cidrhost()` anywhere in `modules/network`. Subnet CIDRs are supplied as explicit, hand-written lists by the caller. This is a deliberate design choice with a real trade-off (see bottom).

---

## Manual calculation

### Q1: How many addresses in `10.40.0.0/16`?
/16 → 32 − 16 = 16 host bits → 2^16 = **65,536 addresses**, range `10.40.0.0` – `10.40.255.255`.

### Q2: How many in each `/24`?
/24 → 8 host bits → 2^8 = **256 addresses**.
AWS reserves **5 per subnet**:
- `.0` — network address
- `.1` — VPC router
- `.2` — AWS DNS (the "VPC+2" resolver)
- `.3` — reserved for future use
- `.255` — broadcast (reserved even though AWS doesn't support broadcast)
→ **251 usable** per /24.

### Q3: Total consumed by the 6 configured subnets?
6 × 256 = **1,536 of 65,536 = 2.34% utilisation**. Enormous headroom — a /16 can hold **256** non-overlapping /24s.

### Q4: Does the design support 1 AZ? 2 AZ? 3 AZ?
The *CIDR space* supports far more than 3. The *configuration* supports exactly as many AZs as there are entries in each list — and this is where the real constraint lives (see Q6).

Observed numbering convention (a deliberate design detail worth noticing):
| Tier | Third octet block | Room before collision |
|---|---|---|
| public | `.1`, `.2` | up to `.10` → 10 AZs |
| private_db | `.11`, `.12` | up to `.20` → 10 AZs |
| private_app | `.21`, `.22` | up to `.30` → 10 AZs |

Each tier gets a reserved block of 10 third-octet values, so the scheme scales cleanly to ~9-10 AZs per tier without ever colliding. No AWS region currently has more than 6 AZs, so this is comfortable.

### Q5: 3-AZ extension (manual derivation, following the convention)
```hcl
availability_zones       = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
public_app_subnet_cidrs  = ["10.40.1.0/24",  "10.40.2.0/24",  "10.40.3.0/24"]
private_db_subnet_cidrs  = ["10.40.11.0/24", "10.40.12.0/24", "10.40.13.0/24"]
private_app_subnet_cidrs = ["10.40.21.0/24", "10.40.22.0/24", "10.40.23.0/24"]
```

### Q6: **What breaks if you add an AZ but forget a CIDR?** (the important one)
`aws_subnet.private_app` does `count = length(var.availability_zones)` but indexes `var.private_app_subnet_cidrs[count.index]`. If `availability_zones` has 3 entries and `private_app_subnet_cidrs` has 2, `count.index == 2` indexes past the end of the list → **`Error: Invalid index`** at plan time.

This is a **latent coupling between four separate variables** (`availability_zones` + the three CIDR lists) that Terraform does **not** validate. The module validates `private_app_nat_mode` values and `interface_endpoint_services` names, but has **no `validation` block asserting that all three CIDR lists have the same length as `availability_zones`.** Failing at plan time with "Invalid index" is survivable but unhelpful; a `validation` block could say exactly what's wrong. **Documented as a weakness, not fixed** (Phase 2 is analysis-only; also see `REUSE-AUDIT.md` — the lm-academy repo's `precondition` pattern is the idiomatic fix).

### Q7: What if you change the VPC CIDR but not the subnet CIDRs?
`10.40.x.x/24` subnets inside a `10.50.0.0/16` VPC → **`InvalidSubnet.Range`** from AWS at apply time (subnet CIDR must be within the VPC CIDR). Terraform `validate` will NOT catch this — it's a plan/apply-time AWS API rejection, since Terraform doesn't do CIDR containment math here (no `cidrsubnet()` to derive them).

---

## Manual math vs Terraform implementation

| | Manual/expected | Blueprint actual | Match? |
|---|---|---|---|
| Addresses per /24 | 256 (251 usable) | not computed by Terraform — literal strings | n/a |
| Subnet CIDR derivation | could be `cidrsubnet("10.40.0.0/16", 8, k)` | **explicit hand-written lists** | Deliberate deviation |
| Containment validation | none | **none** | Confirmed gap |
| List-length validation | none | **none** | Confirmed gap |

## Why hand-written lists instead of `cidrsubnet()`? (the trade-off)
- **Cost**: no automatic scaling; adding an AZ means editing 4 variables in lockstep (Q6's failure mode).
- **Benefit**: the CIDR plan is *explicit and auditable*. In a real organisation, IP ranges are typically allocated centrally by a network team and handed to you as fixed values — you often **cannot** let Terraform derive them, because `10.40.21.0/24` was assigned to you specifically. `cidrsubnet()` derivation is elegant until a human needs to reconcile your VPC against a corporate IPAM spreadsheet.
- **Contrast**: `aws-ia/terraform-aws-vpc` (audited this phase) auto-derives CIDRs from subnet *roles* — more convenient, and it actively hides exactly the math this lab exists to teach.
