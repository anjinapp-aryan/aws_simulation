# INCIDENT-06 — BONUS: The Backup Runbook Doesn't Actually Work

**Severity**: SEV-2 (discovered during routine DR verification, not a customer-facing outage)
**Business impact**: none yet — but the organization's actual recovery capability was zero for the entire period this went undetected.
**Initial symptom**: a routine/precautionary backup was attempted (as part of standard practice after other incidents this week) and the `pgbackrest backup` command itself failed.

## What was configured (the hidden fault)
`archive_command` was set to `pgbackrest --stanza=dmeo archive-push %p` — a realistic, single-character typo (`dmeo` instead of `demo`) in the stanza name, the kind of real operator mistake that passes a casual glance.

## Real evidence
1. Attempting a routine full backup: `pgbackrest --stanza=demo --type=full backup` **failed outright** after a 60s timeout: `ERROR: [082]: WAL segment 000000030000000000000004 was not archived before the 60000ms timeout`, with pgBackRest's own hint: `"check the archive_command to ensure that all options are correct (especially --stanza)"`.
2. `pgbackrest --stanza=demo info` (`evidence/incident-06/pgbackrest-info-before-fix.txt`) confirmed: **`status: error (no valid backups)`**, `wal archive min/max: none present` — the DR mechanism had produced **zero usable backups** the entire time `archive_mode` was on, despite `archive_mode`/`archive_command` both being configured and looking superficially correct in `SHOW archive_command`.
3. The gap was discovered **before** any real customer-facing incident required it — a genuinely fortunate timing (the design intent was "discovered mid-incident"; the real execution surfaced it during an unrelated DR-verification drill, which is itself realistic — many real organizations only discover this exact class of gap during a drill, not during a live incident, and that is the better outcome).

## Root cause vs. contributing factor
- **ROOT CAUSE**: a one-character typo in `archive_command`'s `--stanza` argument.
- **CONTRIBUTING FACTOR**: nothing was monitoring `pgbackrest info`'s own `status` field or alerting on `wal archive min/max: none present` — the misconfiguration was invisible until someone manually tried to use it.

## Fix
Corrected `archive_command` to `pgbackrest --stanza=demo archive-push %p` via Patroni's REST API + rolling restart (same technique as R14 Experiment 5), then retook the backup: **succeeded** (`full backup size = 22.5MB`, `backup command end: completed successfully (2600ms)`), confirmed via `pgbackrest info` now showing **`status: ok`** with a real WAL archive range and a real full backup entry.

## Mitigation vs. root-cause fix
**Mitigation**: none needed — no live incident was in progress when this was found (the intentional, better outcome of routine DR verification).
**Root-cause fix**: correct the typo (done); **permanent architectural fix** (proposed, not built): alert on `pgbackrest info`'s machine-readable status (or an equivalent `wal archive min/max: none present` check) on a schedule, independent of whether anyone remembers to manually verify DR readiness.

## Architectural review
1. Why did this go undetected? No automated verification of backup/DR *readiness*, only (implicitly) trust that "the config exists."
2. Blast radius if a real disaster had struck during the gap: total, unrecoverable data loss beyond whatever the last valid backup covered (which, per `pgbackrest info`, was none) — the worst possible RPO.
3. What new failure mode could an aggressive DR-verification alert introduce? Alert fatigue if the check itself is flaky (e.g., transient network blips during a WAL-archive check misreported as "broken") — the check must be robust to transient conditions, not just a single failed probe.

## AWS mapping
Local: a typo'd `archive_command` silently breaking pgBackRest's WAL archiving. AWS analog: an IAM permission drift, an incorrectly-scoped S3 bucket policy, or a mis-tagged resource silently breaking AWS Backup / RDS automated backups while the AWS console still shows the backup job as "configured." Equivalent: the "untested backup is not a backup" lesson (directly reusing R14 Experiment 7's own real finding — a Velero backup that reported `Completed` while silently skipping PV data — now demonstrated a second, independent way for the same class of failure to occur). AWS-only: AWS Backup's own audit/reporting console for backup job history.

## Interview takeaway
**Q: How do you verify a backup is actually recoverable?**
A: Don't trust that a backup mechanism is "configured" — periodically and automatically verify its actual readiness (here: `pgbackrest info`'s own status/WAL-archive-range fields), and treat "no one has tried to restore from it recently" as a real risk, not a comfort. This project has now hit this exact class of gap twice, independently (R14's Velero/hostPath incompatibility, and this incident's typo'd `archive_command`) — different mechanisms, same underlying lesson.
**Key point**: "A backup you haven't tested is a hope, not a backup."

## STATUS: PASS
