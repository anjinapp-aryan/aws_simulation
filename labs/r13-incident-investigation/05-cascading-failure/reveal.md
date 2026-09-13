# R13-05 — SPOILER — ROOT CAUSE

## What was injected
`inject.sh` added a real Toxiproxy `latency` toxic (800ms + 100ms jitter) on **order-service's own** DB connection only (a dedicated `orderdb` proxy). Debezium's CDC connection to `order-db` (a separate, direct connection, per its connector config) is untouched, and payment-service/payment-db are completely untouched.

## Real observed evidence
- Baseline: `place-order` → `CONFIRMED` in ~1.2s (`evidence/timeline.txt`).
- Under fault (`evidence/poll.txt`): order `order-fault1` created at `03:15:50.055`, still `CREATED` at `03:15:53`, flips to `CONFIRMED` only by `03:15:56.895` — a **~6.8s** total round trip, 5.6x baseline.
- `payment-service` logs: `order_id=order-fault1 ... payment COMPLETED` at `03:15:53` — **payment itself finished in ~3s, completely on time.**
- `order-service`'s own confirmation write (the `UPDATE orders SET status='CONFIRMED'` in `consume_payment_events`) is the piece that lands at `03:15:56.895`, ~3.9s **after** payment already completed.

## Root cause
This is a genuine cross-service cascade, but not the one a naive glance suggests: the delay is NOT in payment processing (proven fast, on time) and NOT in Debezium/Kafka relay (both connectors stayed RUNNING throughout, and payment's own outbox event was relayed and consumed promptly — the consumer thread received it right away). The bottleneck is entirely inside **order-service's own DB write when applying the final confirmation** — the same 800ms-latency-compounds-into-seconds pattern seen repeatedly elsewhere in this project (multiple round trips: `SELECT ... processed_events`, `UPDATE orders`, `INSERT ... processed_events`, `COMMIT`, each paying the toxic). From the customer's point of view this looks like "the whole checkout Saga is slow," but the actual fault is isolated to one service's one dependency — proven by correlating payment-service's own timestamp against order-service's.

## Immediate mitigation
Remove the latency toxic (`fix.sh`).

## Permanent fix / prevention
- Instrument each Saga participant's own step latency separately (not just end-to-end order status) so "the Saga is slow" can be immediately attributed to the correct service instead of investigated from scratch each time.
- Batch the confirmation write's several round trips into fewer statements (e.g., a single `INSERT ... ON CONFLICT DO NOTHING RETURNING` combined with the `UPDATE` in one round trip) so a single slow dependency multiplies less.

## AWS mapping
A Step Functions/EventBridge-driven Saga where one participant's own RDS write is slow — the overall Saga appears delayed, but the delay is isolable to one state's execution time, not the orchestration itself. Directly reuses R11's already-proven real Debezium/Kafka outbox mechanism unmodified.
