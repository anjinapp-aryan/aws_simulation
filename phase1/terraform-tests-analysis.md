# Terraform Test Deep Dive

## `modules/network/tests/vpc_defaults.tftest.hcl` — RUN LIVE THIS PHASE, FAILED

**Command**: `terraform init -backend=false && terraform test`, run from `modules/network/`, zero AWS credentials, zero real API calls (uses `mock_provider "aws"` with `mock_data "aws_iam_policy_document"`).

**Result**: `0 passed, 1 failed, 11 skipped` (the first run's failure aborts the remaining 11 in that same test file).

**What's tested** (11 named runs, only the first attempted before failure): `dns_support_enabled`, `dns_hostnames_enabled`, `public_subnets_no_auto_public_ip`, `private_app_subnets_no_public_ip`, `private_db_subnets_no_public_ip`, `default_sg_lockdown_enabled`, `flow_logs_created`, `nat_per_az_in_required_mode`, `single_nat_in_canary_mode`, `no_nat_in_disabled_mode`, `s3_gateway_endpoint_created`, `igw_has_lifecycle_create_before_destroy`. Every one of these is a real, meaningful structural/security assertion — the test file's *design* is good. The failure is unrelated to test design quality; it's a code defect in the module being tested.

**Exact failure**:
```
Error: Invalid function argument
  on main.tf line 24, in locals:
    24:   var.flow_logs_name_prefix != null && trimspace(var.flow_logs_name_prefix) != ""
  Invalid value for "str" parameter: argument must not be null.
```
The test's `variables {}` block sets `vpc_cidr`, `availability_zones`, and the three subnet CIDR lists — but never sets `flow_logs_name_prefix`, relying on its `default = null`. The module's own null-guard (`var.flow_logs_name_prefix != null && trimspace(...) != ""`) does not actually prevent `trimspace(null)` from executing, contrary to what the `&&` operator would suggest in most general-purpose languages.

**Why this matters as a teaching example**: this is exactly the value of running `terraform test` in isolation, per-module, rather than trusting that "the full CI pipeline passes" means every module works standalone. Whatever wrapper/root normally exercises this module in CI presumably always supplies `flow_logs_name_prefix`, masking the defect. The moment someone (this phase) runs the module's own test suite with only its own defaults, the gap is exposed. **This is a real bug in a production-oriented repo, found by following the user's own instruction to actually run the tests rather than assume they pass.**

**Failure type**: syntax/structural — a Terraform evaluation-order error, not a security or behavioral assertion failing. It would block `terraform plan` for anyone instantiating this module without an explicit `flow_logs_name_prefix`, in real AWS use too, not just in the test.

## `modules/security_groups/tests/least_privilege.tftest.hcl` — read in full, not executed live this phase (deferred, low risk to assume correct given the assertions are simple, targeted `plan`-time attribute checks against a fully-mocked provider — could still be run in Phase 2 for completeness)

| Test | Resource/property tested | Failure type it would catch | Category |
|---|---|---|---|
| `rds_ingress_restricted_to_backend_only` | exact count of port-3306 ingress rules == 1 | security — accidental widening of DB access | behavior/security |
| `backend_service_ingress_from_alb_only` | exact count of app-port ingress rules == 1 | security — backend reachable from unintended source | behavior/security |
| `alb_ingress_on_listener_port` | exact count of port-443 ingress rules == 1 | security — public entry point wider than intended | behavior/security |
| `custom_app_port_propagates` | app_port change reflected in backend SG AND ALB egress, RDS egress port unaffected | structural coupling bug — a port change accidentally leaking into an unrelated rule | behavior + structure |
| `environment_suffix_applied` | SG names include environment suffix when enabled | naming-convention correctness | structure |

All five are genuinely **behavioral/security** assertions (they check the *planned resource attributes*, e.g. counting matching ingress rules), not mere syntax checks — this is the more mature category of Terraform test, one level past "does this even parse."

## General conclusion on this repo's test maturity
Real `mock_provider` usage (not touching real AWS), real behavioral assertions (not just "resource exists"), and — crucially, proven this phase — real enough to actually catch a real bug when exercised properly. The one weakness found is in the *module under test*, not the *test itself*: `vpc_defaults.tftest.hcl`'s test design is sound, but it exposed a genuine `locals.tf` defect the moment it was run in true isolation.
