# R13-05 — INCIDENT: Orders stuck in CREATED longer than expected

**Symptom:** customers report their order status stays "CREATED" for much longer than usual before flipping to CONFIRMED, even though payments appear to be processing normally.
**Scope:** order-service specifically; check whether payment-service is also affected.

## Available tools
- Kafka UI: http://localhost:56080
- pgweb (order-db): http://localhost:56081
- pgweb (payment-db): http://localhost:56082
- Debezium Connect REST: http://localhost:56083/connectors
- order-service: `GET http://localhost:56000/order-status?id=<id>`
- Container logs: `docker compose logs order-service` / `payment-service`

## Task
Follow the 12-step investigation. Key question: is payment-service processing payments on time? Is Debezium relaying events on time? Where exactly does the delay live — publish, relay, or the final status-write step?
