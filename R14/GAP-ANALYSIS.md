# R14 — Gap Analysis: What R1–R13 Have NOT Taught

## 1. Coverage matrix

| Capability | Covered by | Depth | Real/Equivalent | Remaining gap | Senior Architect importance | R14 relevance |
|---|---|---|---|---|---|---|
| App-tier self-healing/rolling update | R10 | Deep, under real failure | REAL | none | High | — |
| App-tier autoscaling (HPA) | R10 | Deep, real metrics-driven | REAL | none | High | — |
| DB connectivity/connection pooling | R4, R13-01 | Deep, under real load | REAL | none | High | — |
| **DB primary failure / automatic failover** | — | **Never tested** | — | **Total gap** | **Very High** | **Core** |
| Cache failover (Sentinel) | R6 | Deep, real 6s failover measured | REAL | none | High | — |
| Messaging reliability (DLQ/retry/ordering) | R7 | Deep | REAL | none | High | — |
| Distributed tracing/correlation | R8, R13 | Deep | REAL | none | High | — |
| Circuit breaking / outlier ejection | R9, R13-02 | Deep, multi-replica proven | REAL | none | High | — |
| Kubernetes orchestration primitives | R10 | Deep | REAL | none | High | — |
| Distributed transactions (Saga/outbox) | R11, R13-05/08 | Deep, including silent-failure modes | REAL | none | High | — |
| Zero-trust networking | R12, R13-06 | Deep | REAL | none | High | — |
| Symptom-first multi-signal investigation | R13 | Deep, 8 scenarios | REAL | none (methodology, reusable) | Very High | Methodology to reuse, not repeat |
| **Backup / Restore** | — | **Never tested** | — | **Total gap** | **Very High** | **Core** |
| **RTO / RPO measurement** | — | **Never tested** | — | **Total gap** | **Very High** | **Core** |
| **Multi-AZ / failure-domain modeling** | R6 (cache only) | Shallow — only cache tier | Partial | DB and app tiers never tested for AZ-style failure domains | High | Core |
| **Active-Passive vs Active-Active trade-off** | — | Never exercised, only described | — | Total gap | High | Core |
| **Data replication consistency (sync vs async)** | R6 (Valkey async replication, not stressed) | Shallow, never measured for lag/data-loss window | Partial | Never measured replication lag or data-loss window under failure | High | Strong candidate |
| **Capacity planning / right-sizing** | R10 (HPA reacts to load) | Shallow — reactive scaling only, no proactive sizing exercise | Partial | Never compared over- vs under-provisioning cost/reliability trade-off | Medium-High | Possible, weaker fit |
| **Cost vs reliability trade-off (quantified)** | Discussed narratively in every report's "AWS mapping"/interview sections | Never quantified or measured | Theoretical only | Never actually measured (e.g., $/replica vs downtime-seconds) | Medium | Possible, weaker fit — hard to make $0 AND quantify $ cost meaningfully |
| Multi-region / regional failure | — | Never touched | NOT POSSIBLE LOCALLY (no real multi-region primitive to fake honestly) | Total, but largely out of $0-local reach | High in theory | Reject — see below |

## 2. What this shows

Every mechanism-level AWS-adjacent capability (compute, cache, queue, tracing, resilience, orchestration, transactions, network security, and now investigation methodology) has been built and genuinely broken/observed/fixed at least once. The one clear, large, **untouched** category across all 13 phases is **the primary datastore's own availability and recoverability**: no phase has ever killed a primary database and measured what happens, backed one up, restored it, or put a number on "how much data would we lose" / "how long would this actually take to come back." This is also the single most commonly asked Senior/Architect interview area (RDS Multi-AZ, RTO/RPO, DR runbooks) that R1–R13 currently answers only narratively, never with evidence.

Capacity planning and quantified cost/reliability trade-offs are real gaps too, but weaker candidates: HPA already exercises *reactive* capacity response (R10), and a $0 lab cannot honestly attach real dollar costs to anything (AWS pricing isn't observable locally), so "cost vs reliability" would end up asserted, not measured — against this project's core discipline.

Multi-region/regional failure is rejected outright: there is no honest local primitive for "AWS region," and faking one would violate the "never fake AWS behavior" rule.

## 3. Conclusion

**R14's evidence-backed gap is HA / DR / Backup-Restore / RTO-RPO for the primary datastore**, extended to a real Active-Passive vs Active-Active architectural trade-off. This is picked up in `ARCHITECTURE.md` after the reuse and visualization audits below.
