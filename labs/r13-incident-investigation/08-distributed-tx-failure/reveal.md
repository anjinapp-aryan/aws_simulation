# R13-08 — SPOILER — ROOT CAUSE

## What was injected
`inject.sh` called the real Kafka Connect REST API: `PUT /connectors/order-outbox-connector/pause` — a genuine, real connector lifecycle state (not a crash, not a killed container). 3 orders were then placed while paused.

## Real observed evidence
- `order-service`'s own logs (`evidence/order-service-logs-clean.txt`): every request returns `200` — **nothing looks wrong from inside order-service.** This is the trap the investigation warns about.
- `outbox` table row count on `order-db` (`evidence/outbox-count.txt`): **4** (1 baseline + 3 new) — the local transaction (order INSERT + outbox INSERT) genuinely succeeded every time; the dual-write problem is NOT what's broken here.
- Kafka Connect REST status (`evidence/connector-status.txt`): `"connector":{"state":"PAUSED"}` — the CDC relay itself is the thing that's down.
- `order-status` after a 15s wait (`evidence/status-after-15s.txt`): all 3 orders still `CREATED`, `created_at == updated_at` (never touched again).

## Root cause
The write path (order-service → order-db, one local transaction) works perfectly — this is exactly what R11 already proved solves the dual-write problem. What's broken is downstream: Debezium's connector is `PAUSED`, so outbox rows accumulate in the table but are never picked up and relayed to Kafka, so payment-service never even sees the `OrderCreated` event, so it never processes a payment, so no `PaymentCompleted`/`PaymentFailed` event ever comes back, so order-service's own consumer thread has nothing to react to. **The system's own error handling has nothing to report because, from every component's own point of view, nothing has failed** — this is a genuinely silent failure mode, and the investigation must go outside any single service's logs (to the outbox table directly, and to the Connect REST API) to find it.

## Immediate mitigation
Resume the connector (`fix.sh`) — outbox rows that already accumulated get picked up and relayed once resumed (Debezium replays from the WAL position it was paused at, no data loss).

## Permanent fix / prevention
- Alert directly on Kafka Connect connector/task state != RUNNING (`GET /connectors/<name>/status`) — the single most precise, fastest signal for this exact failure.
- Add a backstop alert independent of connector health: outbox rows with `processed = false` (or no matching row appearing in the destination topic) older than N seconds — catches this even if the connector reports a healthy status while still not actually relaying (a stricter check than state alone).

## AWS mapping
An AWS DMS (Database Migration Service) CDC task stopped/paused while the source RDS keeps accepting application writes normally — a real, easy-to-miss AWS incident category, since the source database and the application both report "healthy" throughout.
