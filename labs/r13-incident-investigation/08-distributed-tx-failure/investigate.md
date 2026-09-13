# R13-08 — INCIDENT: Orders stuck in CREATED forever

**Symptom:** customers report orders never leave "CREATED" status. No errors in order-service's own logs.
**Business impact:** payments may or may not actually be happening — unclear from the customer-visible state.

## Available tools
- Kafka UI: http://localhost:53080
- pgweb (order-db): http://localhost:53081
- pgweb (payment-db): http://localhost:53082
- Debezium Connect REST: http://localhost:53083/connectors
- order-service: `GET http://localhost:53000/order-status?id=<id>`

## Task
Follow the 12-step investigation. order-service's own logs show nothing wrong — that's the trap. Where do you look next? Is the outbox table actually growing? Is the topic actually receiving new messages? What does the Kafka Connect REST API say about connector health?
