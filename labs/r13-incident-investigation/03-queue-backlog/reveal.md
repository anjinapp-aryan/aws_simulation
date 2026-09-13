# R13-03 — SPOILER — ROOT CAUSE

## What was injected
`inject.sh` added a real Toxiproxy `latency` toxic (800ms + 100ms jitter) on the consumer's DB path only (the AMQP path to RabbitMQ is untouched), then published 60 "normal" orders as fast as possible.

## Real observed evidence
- RabbitMQ Management API (`evidence/queue-during-incident.txt`): `messages: 58`, **consumer ack rate 0.2 msg/s vs. publish rate 2.6 msg/s** — a real 13x throughput mismatch, with `consumers: 1` (the consumer is genuinely still connected, not dead).
- Consumer's own logs (`evidence/consumer-slow-log.txt`): baseline `db_write=0.014s` → under fault `db_write=6.25-6.54s` per message — an 8x multiplier over the nominal 800ms toxic, consistent with this project's repeatedly-observed finding (R4/R6/R7/R8/R9/R11) that injected latency compounds across multiple TCP round trips of a protocol handshake. Here: opening a fresh psycopg2 connection per message (no pooling in this consumer) plus a `CREATE TABLE IF NOT EXISTS` and an `INSERT` each add their own round trip, each paying the 800ms toxic.

## Root cause
The consumer is alive and correctly acking messages (`consumers: 1`, ack rate > 0) — this rules out "consumer crashed/hung" as a hypothesis. The real cause is a downstream dependency (DB) slowdown that reduced the consumer's *effective* throughput far below the publish rate, so the queue depth grows even though nothing is actually broken in the messaging layer itself. A naive "consumer connected = healthy" check would have missed this entirely.

## Immediate mitigation
Remove the DB latency toxic (`fix.sh`) — consumer throughput recovers and the backlog drains.

## Permanent fix / prevention
- Alert on the *ratio* of ack rate to publish rate (or on queue-depth trend, not just absolute depth) rather than only "is a consumer attached" — a connected-but-slow consumer looks healthy on the naive check.
- Consider connection pooling in the consumer (it currently opens a new DB connection per message) so a single slow dependency doesn't multiply into several round trips per message.
- Add consumer autoscaling keyed on queue depth / consumer lag.

## AWS mapping
SQS backlog / consumer (Lambda or EC2 worker) lag growing because its downstream RDS is degraded — the classic "the queue isn't the problem, the queue is just accurately reporting a downstream problem" SQS incident.
