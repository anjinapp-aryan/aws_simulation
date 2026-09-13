# R15 — Failures and Fixes (building the standing system + running incidents)

## Bug 1 — Debezium `createdat` type mismatch (`TIMESTAMPTZ` vs `TIMESTAMP`)
**Symptom**: `order-outbox-connector` task `FAILED` with `DataException: Field 'createdat' is not of type INT64`, while the connector itself stayed `RUNNING` (a real, easy-to-miss distinction — the connector-level state doesn't reflect a per-task failure).
**Root cause**: the outbox table used `TIMESTAMPTZ`, which Debezium maps to a `ZonedTimestamp` (string) logical type; the EventRouter SMT's timestamp field requires the `int64` (epoch-millis) mapping that only plain `TIMESTAMP` gets.
**Fix**: matched R11's own proven `TIMESTAMP` column type exactly.

## Bug 2 — Patroni's demo cluster defaults to `wal_level=replica`
**Symptom**: would have blocked the order-side Debezium connector entirely (logical replication requires `wal_level=logical`).
**Fix**: `PATCH /config` via Patroni's own REST API (same technique as R14 Experiment 5's `archive_mode` fix) + rolling `patronictl restart`.

## Bug 3 — Git-Bash background-subshell output loss (recurred a third time, across R13/R14/R15)
**Symptom**: a 20-request concurrent load test using `curl ... &` inside a `for` loop, redirecting to one shared file, returned only 6 of 20 lines.
**Root cause**: same as R13-01/R14 — many backgrounded processes racing to append to one file lose most writes on this Windows/Git-Bash environment.
**Fix**: one file per background process, concatenated afterward — now a fully internalized, standing pattern for this project.

## Bug 4 (architectural, discovered by design, not accident) — Debezium pinned to a specific Postgres hostname
**Symptom**: `order-outbox-connector` broke with `UnknownHostException: patroni1` immediately after `docker kill demo-patroni1` — Docker's embedded DNS stops resolving a killed container's name.
**Root cause**: the connector config used a literal node hostname instead of a leader-following mechanism — this is the deliberate architectural weakness Incident 2 was designed to surface, and it worked exactly as intended, with one extra, unplanned finding below.
**Fix**: repoint + recreate the connector against the new leader's hostname.

## Bug 5 (real, unplanned) — Recreating the Debezium connector with a fresh slot silently drops in-flight orders
**Symptom**: 5 orders committed to the database during/just after the outage never confirmed, even after the connector was "fixed" and confirmed `RUNNING`.
**Root cause**: creating a new connector allocates a new replication slot starting from the current WAL position — it does not retroactively replay WAL segments the OLD (now-deleted) connector's slot had already advanced past, silently dropping any commits that fell in that gap.
**Fix**: none applied (would require a manual reconciliation/backfill, explicitly out of scope — documented as an open item in `INCIDENT-02.md`, not hidden).
**Why this matters**: this was NOT part of the Phase A design — it was discovered live, during real execution, exactly the kind of unexpected-bug-as-valuable-evidence this project's standing rule exists to capture.

## Bug 6 (real, but disproven as a "bug" upon investigation) — Hypothesized app-level recovery complication (Incident 4)
**Symptom expected**: DB recovers, app doesn't.
**Real result**: no gap observed — PgBouncer transparently reconnected, and the app's own stateless-per-request design meant there was no long-lived connection to go stale.
**Disposition**: not a bug — a hypothesis tested and honestly reported as disproven, per `INCIDENT-04.md`.

## Bug 7 (deliberately injected, not a real bug, but real tooling behavior worth noting) — `pgbackrest backup` fails LOUDLY, not silently, when `archive_command` is broken
**Observation**: unlike a scenario where a broken backup silently "succeeds" with no data, pgBackRest's own real behavior is to time out and fail the `backup` command outright after 60s when WAL archiving isn't working — a genuinely reassuring real finding about pgBackRest's own design (it does not let you believe you have a backup when you don't), discovered by actually running the command rather than assumed from documentation.
