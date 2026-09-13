# INCIDENT 01 — STARTED

**Time**: see `evidence/incident-01/timeline.txt` for exact timestamps.
**Customer impact**: checkout requests are slow. Some customers report the page "hangs" before showing a confirmation.
**Known symptoms**:
- `/order-status` and `/place-order` p95 latency has increased.
- No error-rate increase reported yet.
- Kafka/order-confirmation pipeline not reported as impacted (unconfirmed — verify).

**Available tools**: Grafana (http://localhost:59300), Prometheus (http://localhost:59090), Jaeger (http://localhost:59686), Dozzle (http://localhost:59888), pgweb-order (http://localhost:59081), Envoy admin (http://localhost:59901), Kafka UI (http://localhost:59180), `patronictl list`.

**Root cause**: UNKNOWN. Investigate.
