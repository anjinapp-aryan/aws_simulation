# Phase 3 Failure Scenarios — Designed, Not Executed

**None of these were run.** Scenarios 1–4 require running ECS (Phase 5) and RDS (Phase 6). Per the roadmap rule, the roadmap is **not** reordered to run them earlier. This document is the design + diagnostic runbook, written *before* execution so diagnosis isn't contaminated by knowing the injection.

Reusable source: `sample-devops-agent-ecs-workshop` labs 2 and 4 — **ADAPT** (their discovery filters target `retail-store-ecs-cluster` / `tag:ecsdevopsagent`, which won't match Blueprint resources). `fix.sh` is the **answer key** — not to be run before diagnosis.

---

## Scenario 1 — Execution role loses ECR permission
**Injection**: detach the execution role's ECR-granting managed policy (`AmazonECSTaskExecutionRolePolicy`).

| Step | Detail |
|---|---|
| **SYMPTOM** | Task never reaches RUNNING; service stuck deploying |
| **FIRST CHECK** | `aws ecs describe-tasks --cluster <c> --tasks <t> --query 'tasks[].stoppedReason'` |
| **EVIDENCE** | `CannotPullContainerError` + an **authorization** error string |
| **HYPOTHESES** | (a) execution role lacks ECR perms; (b) missing `ecr.api`/`ecr.dkr` endpoint; (c) missing S3 gateway endpoint; (d) image tag doesn't exist |
| **DISCRIMINATOR** | **`AccessDenied`/authorization wording → IAM. Timeout/connection wording → network.** This single distinction separates (a) from (b)/(c) immediately |
| **ROOT CAUSE** | Execution role cannot call `ecr:GetAuthorizationToken`/`BatchGetImage` |
| **FIX** | Re-attach the policy (Terraform-managed: re-apply, don't click-fix) |
| **VALIDATION** | Task reaches RUNNING; `describe-tasks` shows no `stoppedReason`; a fresh deployment succeeds |

## Scenario 2 — Execution role loses CloudWatch Logs permission
**Injection**: remove `logs:CreateLogStream` / `logs:PutLogEvents` from the execution role.

| Step | Detail |
|---|---|
| **SYMPTOM** | **Task fails to start** — *not* "logs are missing" |
| **FIRST CHECK** | `stoppedReason` again |
| **EVIDENCE** | `ResourceInitializationError` referencing the `awslogs` driver |
| **KEY INSIGHT** | `modules/ecs_service/locals.tf` sets `logDriver = "awslogs"`. That driver **cannot buffer indefinitely** — if it can't reach CloudWatch at startup, the container does not start. "No logs" and "won't start" are the same root cause |
| **WHY THE PERMISSION IS NEEDED** | `CreateLogStream` (one stream per task, created at launch) + `PutLogEvents` (write). The log **group** is Terraform-created; the **stream** is created per-task at runtime, by the execution role |
| **FIX / VALIDATION** | Restore permission; task starts; a new log stream appears in the expected group |

## Scenario 3 — Task role loses an application permission
**Injection**: remove an application permission (e.g. `s3:GetObject`) from the **task** role.

| Step | Detail |
|---|---|
| **SYMPTOM** | Container **starts normally and stays RUNNING**; a specific application feature fails |
| **FIRST CHECK** | **Application logs — not `describe-tasks`.** ECS reports the task perfectly healthy |
| **EVIDENCE** | `AccessDenied` from an AWS SDK call, naming principal/action/resource |
| **ROOT CAUSE** | Task role lacks the action |
| **WHY THIS SCENARIO EXISTS** | It is the deliberate counterpart to Scenarios 1–2 and the whole point of the role split: **execution-role failure = startup failure visible in ECS; task-role failure = runtime failure visible only in app logs, on a "healthy" task.** If someone reports "task is running but the app gets AccessDenied," the execution role is irrelevant |
| **FIX / VALIDATION** | Grant the narrow action via `task_role_policy_json`; feature works; no other permission was widened |

## Scenario 4 — ECS → RDS Security Group rule removed (adapts workshop lab 4)
**Injection**: remove the RDS SG's ingress rule that references the backend service SG.

| Step | Detail |
|---|---|
| **SYMPTOM** | Application cannot connect to the database; connection attempts hang |
| **FIRST CHECK** | Recognise this is **intra-VPC** traffic — the implicit `local` route always exists, so routing is almost never the cause. Go straight to SGs |
| **EVIDENCE** | `aws ec2 describe-security-groups --group-ids <rds-sg> --query 'SecurityGroups[].IpPermissions'` → no 3306 ingress |
| **DISCRIMINATOR** | **Timeout = dropped by SG.** "Connection refused" = reached the host, nothing listening. "Auth failed" = credentials, not network |
| **ROOT CAUSE** | RDS SG has no ingress permitting the backend SG on 3306 |
| **FIX** | Restore `source_security_group_id = <backend SG>` on port 3306 — **never** `cidr_blocks = ["0.0.0.0/0"]` |
| **VALIDATION** | App connects; `least_privilege.tftest.hcl` still passes (**exactly one** 3306 ingress rule — proving the fix didn't over-grant) |

**Note the elegance**: the existing test doubles as fix-validation. A lazy fix (opening 0.0.0.0/0) would restore connectivity *and fail the test*.

## Scenario 5 — Over-permissive SG, corrected (zero-cost, doable now)
This one needs no AWS — it is a Terraform-level comparison.

**Bad:**
```hcl
ingress {
  from_port   = 3306
  to_port     = 3306
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]     # ← every IP on the internet
}
```
**Good (what Blueprint does):**
```hcl
source_security_group_id = aws_security_group.backend_service.id
```

| | CIDR `0.0.0.0/0` | SG reference |
|---|---|---|
| Who can connect | anyone who can reach the ENI | only members of that SG |
| Survives subnet renumbering | ❌ silently wrong | ✅ |
| Future workload in same subnet | ❌ silently granted access | ✅ not granted |
| Expresses intent | ❌ requires a lookup | ✅ self-documenting |
| Caught by existing test | ✅ **fails `== 1` assertion** | ✅ passes |

**Why the second is superior**, stated for interview use: a CIDR rule grants access to *whatever happens to occupy that address range in future*; an SG reference grants access to *a specific identity*. In a VPC where subnets get reused, that difference is the gap between least privilege and accidental exposure. And note the RDS case is not merely untidy — a publicly-reachable database is among the highest-severity cloud misconfigurations, typically exploited by internet-wide scanners within hours.

---

## Execution plan (deferred, per roadmap)
| Scenario | Needs | Runs in |
|---|---|---|
| 1, 2, 3 | running ECS | **Phase 5** |
| 4 | running ECS + RDS | **Phase 6** |
| 5 | nothing | **available now** (Terraform-level reasoning, already documented above) |

Adaptation work required before running 1–4: rewrite the workshop scripts' resource-discovery filters (cluster name, SG tag selectors) to match Blueprint naming, keeping their injection logic, `/tmp` state backup, and restore paths intact.
