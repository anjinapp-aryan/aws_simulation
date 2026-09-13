# R15 — GitHub Reuse Audit

Standing rule: REUSE > ADAPT > COMPOSE > REFERENCE > BUILD. License badges never trusted alone.

## Fault-injection candidates (full detail: `CHAOS-TOOL-AUDIT.md`)
| Repository | License | Verification method | Stars | Activity | Purpose | Decision |
|---|---|---|---|---|---|---|
| `alexei-led/pumba` | Apache-2.0 | Fetched actual `LICENSE` file | 3148 | Active | Docker-native chaos CLI | REFERENCE — real and usable, not adopted (already-proven zero-dependency primitives cover every needed fault type) |
| `chaos-mesh/chaos-mesh` | Apache-2.0 | Fetched actual `LICENSE` file | 7892 | Active | K8s chaos platform (CRDs+controller+dashboard) | REFERENCE — disproportionate machinery for 2 K8s scenarios |
| `litmuschaos/litmus` | Apache-2.0 | Fetched actual `LICENSE` file | 5610 | Active | K8s chaos platform | REFERENCE — same reason as Chaos Mesh |
| `powerfulseal/powerfulseal` | Apache-2.0 (badge) | Not further verified — rejected on activity alone | 1983 | **Stale (last push 2023)** | K8s/cloud chaos | REJECTED — maintenance |

## Application/infrastructure components — 100% REUSE, zero new components
Every service R15's composed system needs already exists, real and proven, in this repo:

| Component | Source phase | Role in R15 |
|---|---|---|
| Traefik (file-provider) | R2/R5/R6/R7/R8 | Entry point / LB |
| Minimal-server app pattern (`psycopg2`, `redis`, `pika`, `kafka-python`) | R4/R6/R7/R8/R11/R13/R14 | Application tier, composed to touch cache+queue+DB+CDC in one stack |
| Valkey (+ Sentinel) | R6/R13 | Cache tier |
| RabbitMQ | R7/R13 | Queue tier |
| Postgres + PgBouncer + Toxiproxy | R4/R8/R9/R13 | Non-HA DB path (for scenarios not exercising R14's HA stack) |
| Patroni + etcd + HAProxy | R14 | HA DB path (for scenarios that must reason about HA/DR behavior mid-incident) |
| Kafka + Debezium | R11/R13 | CDC/outbox path |
| Envoy + PyBreaker | R9/R13 | Circuit breaking |
| Cilium + Hubble (`kind`) | R12/R13 | Network security path |
| Jaeger + OpenTelemetry | R8/R13 | Tracing |
| Prometheus + Grafana | R4/R5/R6/R7/R8/R9/R13 | Metrics |
| Dozzle | most phases | Logs |
| pgweb | R4/R11/R13/R14 | DB state inspection |
| pgBackRest, Velero+SeaweedFS | R14 | Backup/DR |

## Final decision
**COMPOSE.** No project (chaos framework or otherwise) provides "a realistic multi-subsystem incident investigation capstone" — confirmed by the same negative-evidence pattern every prior phase's audit found (broad "incident simulator"/"chaos capstone" searches return only 0-1★ personal repos; the real, usable projects are all single-purpose chaos engines already evaluated and set to REFERENCE above). R15 composes R1-R14's own already-proven components and fault primitives into one standing multi-subsystem system, under a new thin investigation harness following R13's own proven `investigate.md`/`inject.sh`/`reveal.md`/`fix.sh` pattern, extended for multi-fault sequencing and cross-subsystem evidence capture.
