# R1–R5 AWS Honesty Audit

No phase's own documentation was found to claim a false equivalence ("X IS AWS Y"). Every phase's own README/report language, as written, already uses correct hedged framing. This audit did not need to correct any misleading statement — it independently confirms the existing documentation's honesty on this specific dimension.

| Phase | Component | Claim as written | Classification (this audit's own assessment) |
|---|---|---|---|
| R1 | MinIO + `amazon-ecs-local-container-endpoints` | "real SigV4 request validation and real IAM-style policy evaluation ... NOT AWS S3" / "This is REAL protocol behavior; the credentials themselves are a long-lived MinIO user key (not real rotating STS temporary credentials)" | **Correctly self-classified: BEHAVIOR-EQUIVALENT with a REAL sub-mechanism (the official ECS credential-vending image is genuinely from AWS)**. Honest. |
| R2 | Traefik | Never asserted to BE an ALB anywhere found in this audit's review | **Correctly self-classified: BEHAVIOR-EQUIVALENT.** Honest. |
| R3 | `registry:2` + Docker restart policies | Labeled "ECR-equivalent"; restart-policy behavior described as real Docker semantics, not AWS ECS's own scheduler | **Correctly self-classified: BEHAVIOR-EQUIVALENT.** Honest. |
| R4 | Postgres + PgBouncer + Toxiproxy | Never asserted to BE RDS | **Correctly self-classified: BEHAVIOR-EQUIVALENT.** Honest. |
| R5 | Prometheus/Grafana/cAdvisor | Never asserted to BE CloudWatch | **Correctly self-classified: BEHAVIOR-EQUIVALENT.** Honest. |

## Specific misleading patterns searched for and NOT found in R1–R5
"Traefik is ALB." — not found. "PostgreSQL container is RDS." — not found. "Docker scaling is ECS autoscaling." — not found (R3's own `scale.sh` comment explicitly explains its own semantics are "desired_count = which named services are up," not real elastic scaling). "Prometheus is CloudWatch." — not found.

## Verdict
R1–R5's own documentation already applies the "demonstrates the architectural concept of..." framing this audit was asked to enforce. No correction was required on this dimension.
