# R14 — RTO/RPO Summary (all real, measured)

| Experiment | Scenario | T0 | T3 | RTO | RPO |
|---|---|---|---|---|---|
| Exp 3 | Primary kill, DCS-managed failover | 11:06:12.220027 | 11:06:38.484558 | **26.26s** | n/a (measured separately) |
| Exp 4 | Primary kill during network partition (async replication) | 11:11:21.954038 | 11:11:47.977966 | 26.02s | **32 rows lost** (real, non-zero) |
| Exp 5 | pgBackRest full backup + restore | 11:15:20.387922 | 11:15:35.527622 | **15.14s** | **2 rows lost** (WAL not yet archived) |
| Exp 7 | Full `kind` cluster deletion + Velero restore | 11:29:25.478136 | 11:32:03.129601 | **157.65s** | **0** (K8s objects) / **100% of table data** (PV, hostPath/FSB incompatibility) |

## Key distinctions this project's own evidence draws
- **RTO is not one number** — it depends entirely on which recovery path fires: live replica promotion (~26s here) is an order of magnitude faster than a backup restore (~15s for a small dataset, but this scales with data volume, unlike replica promotion) or a full cluster rebuild (~158s, dominated by infrastructure bootstrap time, not data transfer).
- **RPO is never a single guaranteed value under async replication or backup-based recovery** — Experiment 4 measured a real 32-row loss window that would not exist under synchronous replication (a real, quantifiable trade-off, not a theoretical one). Experiment 5 showed RPO is bounded by *WAL archive freshness*, not backup frequency.
- **A "Completed" status is not proof of RPO=0** — Experiment 7's Velero restore reported success while silently failing to restore the PV's actual data, a real, measured RPO of "the entire table" for that specific storage-class/backup-method combination. Every RTO/RPO number in this table was confirmed by directly querying the recovered system's own data, never inferred from a tool's own success message.
