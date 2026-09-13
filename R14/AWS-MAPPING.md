# R14 — AWS Mapping

| Local implementation | AWS concept | What's equivalent | What's different | What cannot be simulated |
|---|---|---|---|---|
| Patroni + etcd + 3x Postgres + HAProxy | RDS Multi-AZ / Aurora | Single-writer, automatic failover on primary loss, health-check-routed endpoint | AWS's failover uses synchronous replication by default (RPO≈0 by design); this lab's async default let Experiment 4 measure real, non-zero data loss | AWS's own internal failover implementation details; the exact 60-120s RDS Multi-AZ failover SLA (this lab measured ~26s at much smaller scale/complexity) |
| `docker pause`/`docker network disconnect` on a replica | An AZ-local network degradation or a replica falling behind | The *effect* (replication lag, unreachability) | AWS's real cross-AZ network characteristics (latency, partition behavior) can't be honestly reproduced on one machine's Docker network | Real AWS network partition behavior between physical Availability Zones |
| pgBackRest full backup + restore (local filesystem repo) | RDS automated backups + point-in-time recovery | Real backup/restore mechanics, real RTO/RPO measurement methodology | AWS ships transaction log backups continuously (~5 min granularity); this lab's WAL-archive-freshness gap (Experiment 5) is the same *class* of limitation at a much smaller time scale | AWS's managed backup storage durability guarantees (11 9's-class S3 durability) |
| Velero + SeaweedFS, `kind` cluster deletion/recreation | AWS Backup / cross-environment DR runbook for EKS | Real full-cluster object backup/restore mechanics | On real EKS, Velero's CSI-snapshot integration with the EBS CSI driver is the standard, fully-supported path for PV data — this lab's specific failure (hostPath + FSB incompatibility) is a `kind`-local storage-class artifact, not representative of a properly-configured EKS+EBS-CSI setup | A genuine separate AWS region/account as the failure domain; AWS's own control-plane availability guarantees for EKS itself |
| `docker stats` resource measurement (Experiment 8) | EC2/RDS instance sizing and Multi-AZ pricing | Real, measured local resource cost of the HA topology | AWS's actual Multi-AZ pricing (~2x Single-AZ instance-hour cost) reflects a managed service's different overhead structure — NOT the same ratio as this lab's ~4x self-managed local memory footprint | Real AWS billing; this project explicitly does not translate local Docker resource usage into an AWS dollar estimate (see Experiment 8's own INFERRED/AWS-ONLY labeling) |

## Explicit AWS-ONLY items (never claimed as simulated by this lab)
- RDS Multi-AZ's exact internal failover implementation and its published SLA numbers.
- AWS's real network topology and latency characteristics between Availability Zones/Regions.
- S3/AWS Backup's durability guarantees.
- Real AWS Multi-AZ/backup pricing (only architectural knowledge, never asserted as measured here).
- EKS's own control-plane management and its own availability guarantees, independent of anything running inside the cluster.
