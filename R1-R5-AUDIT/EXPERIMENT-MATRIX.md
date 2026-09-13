# R1–R5 Experiment Evidence Matrix (all rows re-tested live this session unless marked HISTORICAL-ONLY)

## R1 Experiment Matrix
| Experiment | Implementation | Execution Evidence | Failure Injection | Observation | Verification | Recovery | Reproducible |
|---|---|---|---|---|---|---|---|
| Baseline IAM ALLOW/DENY | PROVEN | PROVEN (live, after manual CRLF fix) | n/a | PROVEN | PROVEN (real MinIO error text) | n/a | **NOT PROVEN as committed** (RED); PROVEN with a documented manual fix |
| Break IAM (remove PutObject) | PROVEN | HISTORICAL-ONLY | PROVEN historically | PROVEN historically | PROVEN historically (real `AccessDenied`) | PROVEN historically | NOT PROVEN this session (blocked by the same CRLF bug, not re-tested) |
| Fix IAM | PROVEN | HISTORICAL-ONLY | PROVEN historically | PROVEN historically | PROVEN historically | PROVEN historically | NOT PROVEN this session |

## R2 Experiment Matrix
| Experiment | Implementation | Execution Evidence | Failure Injection | Observation | Verification | Recovery | Reproducible |
|---|---|---|---|---|---|---|---|
| Baseline traffic distribution | PROVEN | PROVEN (live) | n/a | PROVEN | PROVEN | n/a | PROVEN |
| Health-check failure | PROVEN | PROVEN (live) | PROVEN (real `touch`, container stays up) | PROVEN (100% shift) | PROVEN (independent 10x curl count) | via fix-health.sh | PROVEN |
| Recovery | PROVEN | PROVEN (live) | n/a | PROVEN (alternation resumes) | PROVEN (independent 10x curl count) | PROVEN | PROVEN |

## R3 Experiment Matrix
| Experiment | Implementation | Execution Evidence | Failure Injection | Observation | Verification | Recovery | Reproducible |
|---|---|---|---|---|---|---|---|
| Self-crash → restart | PROVEN | PROVEN (live) | PROVEN (real `os._exit`) | PROVEN (`RestartCount` 0→1) | PROVEN (`docker inspect`, independent) | PROVEN (automatic) | PROVEN |
| OOM / mem_limit | PROVEN | PARTIAL (live) | PROVEN (real allocation vs. real `mem_limit`) | PARTIAL (`RestartCount`/killed exec confirm it fired; `OOMKilled=true` flag not caught in this session's window) | PARTIAL | PROVEN (automatic) | PARTIAL — timing-sensitive, historically required multiple cycles too |
| Scaling | PROVEN | PROVEN (live) | PROVEN (real stop/start) | PROVEN (`docker compose ps -a`) | PROVEN | PROVEN | PROVEN |
| Image version lifecycle | PROVEN | PROVEN (live, pre-existing images) | n/a | PROVEN (`VERSION=1` in response) | PROVEN | n/a | PROVEN (with pre-built images; a from-scratch clone needs `build-push.sh`, which mutates source in place) |

## R4 Experiment Matrix
| Experiment | Implementation | Execution Evidence | Failure Injection | Observation | Verification | Recovery | Reproducible |
|---|---|---|---|---|---|---|---|
| Baseline connectivity | PROVEN | PROVEN (live) | n/a | PROVEN | PROVEN | n/a | PROVEN |
| Latency injection | PROVEN | PROVEN (live) | PROVEN (real Toxiproxy toxic) | PROVEN (real timeout error, real elapsed time) | PROVEN | via remove-latency.sh | PROVEN |
| Latency recovery | PROVEN | PROVEN (live) | n/a | PROVEN | PROVEN | PROVEN | PROVEN |
| Pool exhaustion | PROVEN | PROVEN (live) | PROVEN (real `pgbench`, real PgBouncer limit) | PROVEN (real PgBouncer error text) | PROVEN | automatic | PROVEN |
| Metrics (`pg_up`) | PROVEN | PROVEN (live) | n/a | PROVEN | PROVEN | n/a | PROVEN |
| Network cut / bad credentials | PROVEN | HISTORICAL-ONLY | PROVEN historically | PROVEN historically | PROVEN historically | PROVEN historically | NOT PROVEN this session |

## R5 Experiment Matrix
| Experiment | Implementation | Execution Evidence | Failure Injection | Observation | Verification | Recovery | Reproducible |
|---|---|---|---|---|---|---|---|
| cAdvisor per-container metrics | PROVEN (deployed) | PROVEN broken (live, re-confirmed) | n/a | PROVEN (`{}` empty response) | PROVEN (cross-checked against Prometheus `up`) | n/a — standing limitation with a proven workaround (`docker stats`) | **CONFIRMED CURRENTLY BROKEN, matches existing documentation exactly** |
| CPU stress | PROVEN | PROVEN (live) | PROVEN (real `stress-ng`) | PROVEN (real `docker stats` 200% CPU) | PROVEN (independent metric) | automatic (stress-ng timeout) | PROVEN |
| Memory stress | PROVEN | HISTORICAL-ONLY | PROVEN historically (including an honest first-attempt-missed-OOM investigation) | PROVEN historically | PROVEN historically | PROVEN historically | NOT PROVEN this session |
| Cascading failure | PROVEN | HISTORICAL-ONLY | PROVEN historically | PROVEN historically | PROVEN historically | PROVEN historically | NOT PROVEN this session |
| DB-latency-under-load | PROVEN | HISTORICAL-ONLY | PROVEN historically | PROVEN historically | PROVEN historically | PROVEN historically | NOT PROVEN this session |
