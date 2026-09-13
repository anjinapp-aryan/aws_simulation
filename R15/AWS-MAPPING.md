# R15 — AWS Mapping

| Local capability | AWS analog | Equivalent | Different | AWS-only |
|---|---|---|---|---|
| Standing multi-subsystem compose system | A real production microservices architecture on ECS/EKS + RDS + ElastiCache + MSK | The *shape* of the dependency graph and failure-domain reasoning | Single-machine Docker networking has none of AWS's real cross-AZ latency/partition characteristics | Real inter-AZ network behavior, VPC routing, security groups at the network layer |
| Patroni failover mid-incident (R15-02/04) | RDS Multi-AZ failover during a live incident | Automatic promotion, application reconnection behavior | AWS's failover uses synchronous replication (RPO≈0); timing specifics differ | RDS's actual internal failover implementation |
| Kafka Connect silent pause (R15-05/13-08) | AWS DMS/MSK Connect task silently stopped while source DB keeps accepting writes | The exact "everything looks healthy except the pipe is closed" failure shape | n/a | AWS's own DMS/MSK Connect monitoring/alerting integration specifics |
| Retry-amplification causing a CPU alert (R15-05) | A Lambda/ECS task's own retry policy amplifying a downstream outage into a visible resource-utilization/cost spike | The causal shape (misdirected root-causing) | n/a | CloudWatch's own anomaly-detection behavior for this pattern |
| pgBackRest DR-readiness gap discovered mid-incident (R15-06) | AWS Backup/RDS automated backup silently failing (e.g., IAM permission drift) while backups "exist" in the console | The "untested backup is not a backup" lesson | n/a | AWS Backup's own console/alerting for backup job failures |
| Envoy circuit breaking / outlier ejection (R15-03) | ALB/NLB target-group health checks, or App Mesh/ECS service-mesh outlier detection | Automatic traffic-shifting away from an unhealthy target | n/a | ALB's exact health-check timing/threshold defaults |

## Never claimed
This lab is not AWS. Every mapping above states the architectural concept demonstrated, not an equivalence claim. Real AWS network topology, real managed-service SLAs, and real AWS billing are explicitly out of scope for every R15 scenario, consistent with every prior phase's own AWS-mapping discipline.

## Post-execution confirmation
Every mapping above held up under real execution — none needed revision after Phase B. One additional real finding not anticipated in Phase A: recreating a Kafka Connect connector with a fresh replication slot silently drops in-flight commits (INCIDENT-02) — the AWS analog is a DMS/MSK Connect task restarted from a fresh checkpoint after being reconfigured, an equally real and equally easy-to-miss AWS gap.
