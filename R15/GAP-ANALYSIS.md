# R15 — Gap Analysis

## 1. R1-R14 capability coverage
Every individual AWS-adjacent mechanism (compute lifecycle, LB/health checks, DB+pooling, observability, cache, messaging, tracing, resilience, K8s orchestration, distributed transactions, zero-trust networking, incident investigation methodology, DB HA/DR) has been built and genuinely broken/observed/fixed at least once, each in a single-lab, mostly single-fault context.

## 2. What R13 already covers
Symptom-first investigation methodology: 8 scenarios, **each with exactly one hidden fault**, each scenario a fresh, isolated stack reused from one prior R-lab. Multi-signal correlation was required *within* a scenario (e.g., Grafana+Jaeger, RabbitMQ UI+logs), but never across an entire system with several subsystems live simultaneously, and never with more than one fault active at once, and never involving the HA/DR machinery.

## 3. What R14 already covers
Real HA/DR mechanism proof: Patroni failover, replication lag, RPO under async replication, pgBackRest backup/restore, Velero full-cluster DR — all executed as **planned, announced experiments** ("now I will kill the leader and measure..."), not as symptom-first investigations. The operator always knew exactly what was about to happen and why.

## 4. Remaining capstone gaps (the evidence-based case for R15)
| Gap | Present in R13? | Present in R14? | Needed for Senior/Principal readiness |
|---|---|---|---|
| Multi-signal correlation across a live, multi-subsystem stack | Partial (per-scenario, 2-3 signals) | No (deliberately isolated to Postgres/K8s) | Yes |
| Cascading failure (one root cause producing symptoms in 2+ unrelated subsystems) | No (R13 scenarios were single-hop or two-hop within one dependency chain) | No | Yes |
| Two independent, simultaneously active faults | No (explicitly one hidden fault per scenario) | No | Yes |
| A misleading/red-herring signal that must be disproven | No (R13's symptoms pointed toward the true cause once investigated correctly) | No | Yes |
| Investigating a system that already has HA/DR in place, and having to reason about whether the HA layer itself is masking or worsening the incident | No | No (R14 tested HA/DR directly, not as background infrastructure during an unrelated incident) | Yes |
| Recovery-ordering / prioritization when multiple things are broken (what do you fix first?) | No | No | Yes |
| Root cause vs. contributing factor vs. secondary symptom, explicitly separated | Implicit in R13 write-ups, never a required deliverable | No | Yes |
| Blast-radius / architectural-placement reasoning (where should the circuit breaker/backpressure/fail-open decision actually live) | Touched narratively in R13's interview takeaways | Touched narratively in R14's trade-off experiment | Yes, but as an *investigation output*, not a pre-written comparison table |
| MTTD alongside MTTR/RTO/RPO | RTO/RPO only (R14); no MTTD concept introduced anywhere yet | Yes |
| Post-incident architectural improvement proposal as a required deliverable, grounded in that specific incident's evidence | Present as generic "prevention" bullets in R13 | Present as generic "permanent fix" bullets in R13/R14 | R15 should require this to reference the specific investigation's own evidence, not a template answer |

## 5. Why R15 is necessary
No existing phase forces the investigator to (a) hold multiple live subsystems in their head at once, (b) discover that a symptom in one subsystem is actually caused by a fault in a completely different one, (c) discard a plausible-but-wrong hypothesis using disproving evidence, or (d) make a recovery-ordering decision when more than one thing is broken. These are the specific, evidence-identified gaps R15 closes.

## 6. What R15 will explicitly NOT repeat
- No new fault-injection mechanism (Toxiproxy, `docker kill`/`pause`/`network disconnect`, `stress-ng`, Cilium policy edits, Kafka Connect pause — all already proven, all reused as-is).
- No new visualization tool (Grafana/Prometheus/Jaeger/Dozzle/RabbitMQ UI/Kafka UI/Hubble/pgweb/`patronictl`/`pgbackrest info`/`velero describe` — all already proven, all reused as-is).
- No re-teaching of any single mechanism R1-R14 already proved (e.g., R15 will not re-demonstrate "Patroni fails over" or "Envoy ejects an outlier" as a standalone fact — it will use those *already-proven* mechanisms as background truth the investigator must reason about mid-incident).
- No single-fault, fully-isolated, freshly-built-per-scenario stack — R15 needs one standing composed system with enough subsystems live at once to make cross-subsystem correlation and cascading/multi-fault scenarios possible.
