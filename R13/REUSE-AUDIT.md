# R13 — GitHub Reuse Audit

Standing rule: REUSE > ADAPT > COMPOSE > REFERENCE > BUILD. Real GitHub API checks (stars/license/activity/archived), never trust badges. Multiple query phrasings, negative-evidence searches recorded even when they return 0.

## Searches run (real `api.github.com/search/repositories` calls)

| Query | total_count | Notable results |
|---|---|---|
| `production incident simulator docker` | 2 | `sasi433/production-incident-simulator` (0★), `ma-dev-usa/PagerLab` (0★) — both unlicensed, 0 stars, no real activity/adoption signal |
| `SRE incident simulation training` | 4 | `schnmnty1/OpsAcademy` (1★), `MrEinsteinE/cloud-incident-response-openenv` (0★), `alfonza1/critical-response` (0★, NOASSERTION license), `Ajay-d-1/resilientagent-prod` (0★) — none usable |
| `distributed systems failure simulation lab` | 8 | `akhildec24/FaultLab` (1★), `dram-gh/distributed-system-observability-lab` (0★, MIT), `vaibhavpatil007/production-reliability-lab` (0★), `Vtestcode/AI-System-Design-Simulation-Lab` (0★) — none with real adoption |
| `kubernetes troubleshooting lab hidden fault` | 0 | none |
| `application performance troubleshooting lab observability` | 0 | none |
| `OpenTelemetry demo microservices` | 143 | **`open-telemetry/opentelemetry-demo`** (3339★, Apache-2.0, active, pushed 2026-09-11) and **`aws-samples/one-observability-demo`** (271★, MIT-0, active) — real, mature, high-signal candidates (detailed below) |
| `chaos engineering docker compose lab` | 0 | none |
| `root cause analysis simulation game` | 0 | none |

**Negative-evidence conclusion, per standing methodology**: across 8 distinct query phrasings, every "incident simulator" / "troubleshooting lab" style project with any real signal (stars, license, recent activity) returns **0 results** — every hit is a 0-1★, unlicensed or barely-licensed personal repo with no evidence of real use. This confirms, the same way every prior phase's audit did, that no integrated "hidden-fault production-incident investigation lab" exists as a reusable off-the-shelf project.

## Real, high-signal candidates found (from the OpenTelemetry query) — evaluated in detail

### `open-telemetry/opentelemetry-demo` (3339★, Apache-2.0, active)
The OpenTelemetry "Astronomy Shop" — ~20 polyglot microservices with full OTel instrumentation, and it **does** ship a real `flagd`-based fault-injection mechanism (feature flags like `adServiceFailure`, `cartServiceFailure`, `paymentServiceFailure`, `kafkaQueueProblems`, `recommendationServiceCacheFailure`). This is the closest real match to R13's intent found anywhere.
**Decision: REFERENCE, not REUSE.** Reasons:
1. It replaces the entire application layer with ~20 new polyglot services — directly violates the project's "minimal custom code" and "compose R1-R12's existing minimal app pattern" rules; it is a wholesale second application stack, not a composable fault-injection layer.
2. Its fault injection is feature-flag-based (`flagd` toggling in-process failure branches) rather than infrastructure-level fault injection (Toxiproxy latency, NetworkPolicy denial, OOM) — R13 wants the *investigation methodology*, and R1-R12 already have superior, already-proven infrastructure-level fault primitives (Toxiproxy, Cilium, K8s resource limits) that this project doesn't need to replace.
3. Adopting it would mean re-learning and re-validating an entirely new stack instead of composing already-validated R4/R6/R7/R8/R9/R10/R11/R12 mechanisms — against the standing "don't duplicate R1-R12's underlying tech demos" instruction.

Its value here is as a **design reference**: it validates that "inject a hidden fault via a real mechanism, observe via dashboards/traces, find root cause" is a legitimate, well-precedented pattern for a mature CNCF-adjacent project — corroborating R13's approach rather than replacing it.

### `aws-samples/one-observability-demo` (271★, MIT-0, active)
AWS's own "Pet Adoption" observability demo, designed to run on real EKS/CloudWatch/X-Ray.
**Decision: REJECT for REUSE.** Requires real AWS infrastructure (EKS, managed CloudWatch/X-Ray) to run as intended — violates the project's $0/local-only constraint. Noted as REFERENCE only (confirms AWS's own field pattern for "inject observable failure, use dashboards to find it" matches R13's design intent).

### Other candidates checked and rejected
All four repos surfaced by the "SRE incident simulation" and "distributed systems failure simulation lab" queries (`OpsAcademy`, `cloud-incident-response-openenv`, `critical-response`, `resilientagent-prod`, `FaultLab`, `distributed-system-observability-lab`, `production-reliability-lab`, `AI-System-Design-Simulation-Lab`) were checked: all have 0-1 stars, most have no OSI license (unlicensed = all-rights-reserved, not legally reusable even if code were found useful), and none show real multi-contributor activity. Rejected on license/maturity grounds, consistent with every prior phase's bar for what counts as a genuine reuse candidate.

## Visualization reuse audit

No new dashboard will be built. R13 reuses, unmodified, exactly the visualization surfaces already proven real in prior phases:

| Signal | Tool (already proven real in) |
|---|---|
| Metrics / anomaly detection | Grafana + Prometheus (R4, R5, R6, R9) |
| Distributed traces | Jaeger UI (R8) |
| Queue depth / consumer lag | RabbitMQ Management UI (R7) |
| CDC/outbox event flow | Kafka UI — kafbat fork (R11) |
| Container logs | Dozzle (R1-R9) |
| K8s object/resource state | `kubectl describe`/`get events` (R10) |
| Network policy verdicts | Hubble / Hubble UI (R12) |

## Final reuse decision for R13

**COMPOSE.** No single existing project solves "hidden-fault, multi-signal, investigation-driven incident simulation" end-to-end and reusable at $0 locally. R13 will compose already-proven R4/R6/R7/R8/R9/R10/R11/R12 infrastructure and fault-injection primitives (Toxiproxy, Cilium NetworkPolicy, K8s resource limits, Envoy/PyBreaker, RabbitMQ, Debezium/Kafka) under a **thin, new investigation/evidence-capture harness** (bash scripts that inject a hidden fault, then require the investigator to query the existing dashboards/APIs to find it) — the only genuinely new code this phase needs.
