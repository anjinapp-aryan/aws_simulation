# R3 AWS Mapping

| Local | AWS equivalent | Real or behavioral? |
|---|---|---|
| `registry:2` push/pull | ECR | Real image storage/lifecycle; not ECR's API/IAM/replication |
| Docker container | ECS task | Real process/container lifecycle; not the ECS scheduler |
| `restart: on-failure` (self-crash only) | ECS service replacing a failed task | Behavior-equivalent — **same container ID restarts**, real ECS launches a **new task ID** |
| `docker compose stop/start` (manual) | Operator/console stop-start | Real, but requires manual `start` — no auto-reconciliation, unlike ECS desired-count enforcement |
| Traefik (file provider) | ALB | High-fidelity routing/health-check behavior; not AWS ALB's exact API or deregistration-delay semantics |
| `mem_limit` + real OOM-kill | ECS task memory limit + OOM | Real kernel/cgroup enforcement, same underlying mechanism Fargate itself uses |
| Dozzle | CloudWatch Logs (awslogs driver) | Real stdout/stderr streaming; not CloudWatch's storage/query/alarm layer |
| `docker compose up --...=N` named services | ECS service desired_count | Behavior-equivalent, manually triggered here vs auto-reconciled in ECS |

Not reproduced in R3 (deferred): real Fargate compute isolation, ECS scheduler control-plane behavior, IAM task-role enforcement (covered separately in R1), CloudWatch's actual storage/metrics/alarms.
