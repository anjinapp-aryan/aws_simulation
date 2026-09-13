# R15 — Visualization Audit

No custom UI. Every signal type R15 needs is already served by a tool proven in R1-R14.

| Tool | Purpose | Existing (phase) | Signals | Used in which R15 scenarios |
|---|---|---|---|---|
| Grafana + Prometheus | Golden signals (latency/traffic/errors/saturation), CPU/memory, replication lag, cache stats | R4/R5/R6/R7/R8/R9/R13 | request rate, error rate, p50/p95/p99 latency, container CPU/mem, DB connection count | All scenarios (primary correlation surface) |
| Jaeger | Distributed traces, span-level latency breakdown, dependency graph | R8/R13 | which downstream call is actually slow; cross-service trace propagation | Scenarios involving the app→cache→DB→queue chain |
| Dozzle | Real-time container logs | most phases | app errors, connection pool timeouts, Patroni/etcd promotion logs, Debezium connector state changes | All scenarios |
| RabbitMQ Management UI | Queue depth, consumer count, ack/publish rates | R7/R13 | backlog growth, consumer health | Queue-involving scenarios |
| Kafka UI (kafbat fork) | Topic/consumer-group lag, connector status | R11/R13 | CDC relay lag, connector PAUSED state | CDC/outbox-involving scenarios |
| pgweb | Direct DB row-level inspection | R4/R11/R13/R14 | actual data state, proving/disproving data-loss hypotheses | Scenarios where data correctness must be verified post-recovery |
| `patronictl list` | Real Postgres HA cluster state | R14 | leader/replica identity, replication lag, timeline | HA-involving scenarios |
| `pgbackrest info` | Backup metadata | R14 | last backup time/size, informing RPO reasoning | Backup/DR-involving scenarios |
| Hubble / `hubble observe` | Real network flow verdicts | R12/R13 | ALLOWED/DENIED flows, proving/disproving a network-policy hypothesis | Network-involving scenarios |
| Envoy admin (`/clusters`, `/stats`) | Circuit-breaker/outlier state | R9/R13 | ejection counts, per-host health | Circuit-breaker-involving scenarios |

## Why this satisfies "visualization is mandatory, no custom UI"
Every one of these is a mature, already-integrated, already-proven tool from R1-R14 — the investigator uses the *same* dashboards a real on-call engineer would have, not a bespoke incident-simulator UI. The only genuinely new "interface" is the symptom-only incident brief text (`investigate.md`, following R13's own convention) — which is documentation, not a dashboard, and contains no visualization logic of its own.
