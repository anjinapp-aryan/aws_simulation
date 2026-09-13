# R13-03 — INCIDENT: Order queue backlog growing

**Symptom:** the `orders` queue depth in RabbitMQ is climbing steadily. Consumer shows as "connected" and "running."
**Business impact:** orders are being accepted but processed later and later.

## Available tools
- RabbitMQ Management UI: http://localhost:59672 (guest/guest)
- Grafana: http://localhost:59300
- Prometheus: http://localhost:59090
- Dozzle: http://localhost:59888

## Task
Follow the 12-step investigation. Key question: is the consumer dead, or alive-but-slow? What's the ack rate vs. publish rate? What does the consumer's own processing time per message look like?
