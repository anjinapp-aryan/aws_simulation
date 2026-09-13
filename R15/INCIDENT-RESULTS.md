# R15 — Incident Results Summary

| # | Name | Level | Root cause | Contributing factor | Secondary symptom | MTTR/RTO | RPO | Status |
|---|---|---|---|---|---|---|---|---|
| 01 | Checkout slowness | 1 | DB latency amplified by small PgBouncer pool | Pool sizing | none | fix applied instantly once found | n/a | PASS |
| 02 | Checkout 5xx + stuck orders | 2 | Real Patroni leader failure | Debezium pinned to hostname, not leader-aware | 5xx (auto-resolves) | RTO ≈ 46.5s (app-level) | 5 orders permanently lost from CDC gap (real, measured) | PASS |
| 03 | Slow reads + hard failures | 3 (multi-failure) | TWO independent: Valkey `maxmemory` + Toxiproxy timeout on one replica | n/a (independent) | n/a | both fixed and independently verified | n/a | PASS |
| 04 | DB recovered, is app healthy? | 3/4 | Real Patroni failure (same mechanism as 02) | n/a | n/a | RTO ≈ 46.3s; **hypothesized app-level complication tested and disproven** (PgBouncer recovered transparently) | n/a | PASS |
| 05 | CAPSTONE: confirmations delayed + CPU alert | 5 | Kafka Connect connector silently `PAUSED` | Client retry/poll loop with no backoff | CPU spike (0.5-0.9%→7-8%, real, measured) | resumed within seconds, verified via a specific previously-stuck order confirming | 0 (Debezium resumed from paused WAL position, zero loss) | PASS |
| 06 | Backup runbook doesn't work | bonus | Typo'd `archive_command` (`dmeo` vs `demo`) | No automated DR-readiness verification | Backup command itself failed loudly | discovered pre-emptively during routine verification, not mid-outage | RPO would have been **total** (zero valid backups) had a real disaster struck during the gap | PASS |

## Coverage against required capstone criteria
- Cascading failure: INCIDENT-02 (one root cause, two-subsystem symptoms).
- Multi-failure (independent): INCIDENT-03.
- Misleading/loudest-signal: INCIDENT-05 (CPU alert vs. real cause).
- Recovery ordering reasoned about: INCIDENT-02, INCIDENT-05.
- Root cause vs. contributing factor vs. secondary symptom: every incident's own report.
- Backup/DR gap discovered proactively: INCIDENT-06.
- Hypothesis disproven with evidence (not forced to match the design): INCIDENT-04.
