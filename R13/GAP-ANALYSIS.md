# R13 — Gap Analysis: Production Troubleshooting / Incident Investigation

## 1. What R1–R12 already cover

| Phase | Mechanism | Visualization |
|---|---|---|
| R1–R3 | ECS task identity, ALB routing/health checks, ECS lifecycle | Traefik dashboard, Dozzle |
| R4 | RDS-equivalent DB (Postgres + PgBouncer) + Toxiproxy fault injection | Grafana, Prometheus, pgweb |
| R5 | General observability stack | Grafana, Prometheus |
| R6 | ElastiCache-equivalent (Valkey) cache-aside + Sentinel failover | Grafana |
| R7 | RabbitMQ DLQ / retry / backoff / idempotency / ordering | RabbitMQ Management UI |
| R8 | Distributed tracing (OpenTelemetry → Jaeger), context propagation across MQ | Jaeger UI |
| R9 | Circuit breaking (Envoy outlier detection + PyBreaker) | Envoy admin, Grafana |
| R10 | Real Kubernetes (`kind`): self-healing, rolling update, OOMKill, HPA | kubectl, metrics-server |
| R11 | Outbox/CDC/Saga (Debezium + Kafka) distributed-transaction correctness | Kafka UI (kafbat fork) |
| R12 | Zero-trust networking (Cilium NetworkPolicy/CiliumNetworkPolicy + WireGuard) | Hubble / Hubble UI |

Each phase so far teaches **one mechanism in isolation**, with the root cause of every "break" step already known in advance by the operator (we inject it, we know what we injected). None of them require **correlating multiple independent signals** (metrics → traces → logs → dependency graph) to find a cause that isn't already known going in.

## 2. The actual gap

Real production incidents are never "phase X's single mechanism failed and I already know it." They are:
- **Symptom-first**: you see a dashboard anomaly or a page, not a root cause.
- **Multi-signal**: the real cause is usually 2-3 hops away from the visible symptom (e.g., DB latency → connection-pool exhaustion → app thread starvation → HTTP 5xx), and no single existing lab exercises that *correlation* muscle.
- **Cross-cutting**: real incidents frequently touch more than one of R1-R12's mechanisms in a single event (e.g., a network policy change causing DB timeouts causing a circuit breaker to trip).
- **Investigation discipline**: the actual senior/architect interview skill being tested is not "can you configure Envoy outlier detection" (R9 already proved that) but "given a vague page ('latency is up'), what do you check first, second, third, and how do you rule hypotheses in/out using real evidence."

No phase so far has exercised: (a) a *hidden* injected fault the operator doesn't announce in advance, (b) a structured elimination process across metrics/logs/traces/dependency topology, (c) writing up the investigation itself (not just the fix) as the deliverable.

## 3. What R13 must NOT do

- Must NOT reimplement any of R1-R12's underlying mechanisms (no new cache, no new queue, no new tracing SDK, no new CNI). All fault injection and observability must **reuse existing labs' components/images**, composed differently.
- Must NOT reveal the root cause in the experiment title/description (e.g., never "Postgres killed → DB down"). Titles describe only the **observable symptom**.
- Must NOT require any new custom application logic beyond what's already proven in R1-R12 — this phase is about **composition + investigation scripting**, not new app code.

## 4. Conclusion

R13's unique value is the **investigation layer**: a correlation harness (symptom → dashboard → trace → log → dependency → hypothesis → elimination → root cause → fix → prevention) sitting on top of R4/R6/R7/R8/R9/R10/R11/R12's already-proven mechanisms. This is a composition problem, not a new-build problem — confirmed by the reuse audit below (no integrated tool solves this end-to-end for free).
