# INCIDENT-03 — Slow Reads AND Hard Failures (two independent faults)

**Severity**: SEV-2
**Business impact**: product/order reads slow for everyone; roughly half of read requests to fresh (uncached) orders failed outright.
**Initial symptoms**: Grafana showed both elevated latency and elevated error rate on the same panel, at the same time.

## Investigation
**Trap**: both symptoms appearing together on one dashboard tempts a single-cause assumption.
**Fault A (real)**: Valkey `maxmemory` set to 1mb (below working-set size) + `allkeys-lru` — real evidence: `keyspace_hits:59` vs `keyspace_misses:143` (`evidence/incident-03/valkey-stats.txt`), a genuine cache degradation, not total failure.
**Fault B (real, independent)**: a 2000ms Toxiproxy timeout on `order-service-2`'s own DB path only — real evidence: `evidence/incident-03/status-counts.txt` shows a real mix of `200`s (~45%) and `503`s at consistently ~2.0s (matching the toxic exactly), and Envoy's own outlier stats (`evidence/incident-03/envoy-outlier.txt`) show **`ejections_enforced_total: 15`** — Envoy genuinely detected and cycled the bad replica in and out of rotation.
**Separating the two**: the Valkey hit/miss stat and the Envoy per-host ejection count are two independent, non-overlapping pieces of evidence — neither one explains the other's symptom. Fixing only Fault A would have left the ~50% hard-failure rate untouched; fixing only Fault B would have left elevated latency (from cache misses) untouched.

## Real bug hit during this incident's own execution
The first load-test attempt lost most of its output (curl processes backgrounded via `&` inside a `for` loop, writing to a single shared file) — the same Git-Bash/MSYS output-loss bug already documented in R13-01 and R14. Fixed identically: one file per background process, concatenated afterward. Recorded here rather than silently redone, per the standing "unexpected bugs are valuable evidence" rule.

## Mitigation vs. root-cause fix
Both faults required independent fixes: `valkey-cli CONFIG SET maxmemory 256mb` (Fault A) and removing the Toxiproxy timeout on `orderdb2` (Fault B). Neither fix alone resolved both symptoms — verified independently (post-fix load test: 16/16 non-404 requests returned `200`, zero `503`s).

## Recovery ordering
No strict order was required here (the two faults were independent, not causally chained) — but BOTH were verified independently before declaring the incident resolved, which is the actual lesson: don't stop investigating after the first fix "seems to help."

## Blast radius / architectural review
1. Why did two symptoms coexist? Coincidence of two unrelated real issues, not a shared cause — a genuine multi-failure incident, exactly the R15-03 design intent.
2. Should this have been caught earlier? A cache hit-ratio alert (leading indicator, per R13-07's own lesson) and a per-host Envoy ejection alert (leading indicator, per R15-01/R9's lesson) would each have fired independently, pointing straight at each fault.
3. What new failure mode could a naive "just restart everything" mitigation introduce? Restarting Valkey would clear its (already-thrashing) cache with no lasting effect on the `maxmemory` misconfiguration; restarting order-service-2 would not fix the Toxiproxy toxic still attached to its DB path — both would look like they "worked" (a temporary blip in symptoms) while leaving the real causes in place, a dangerous false-positive mitigation.

## AWS mapping
Fault A: ElastiCache node undersized for its working set (same as R13-07). Fault B: ALB/target-group health-check-driven ejection of one unhealthy EC2/ECS target (same as R9/R13-02). Both are real, independently-documented AWS incident shapes; their simultaneous occurrence here is illustrative composition, not claimed as a common real-world coincidence.

## Interview takeaway
**Q: How do you handle multiple simultaneous failures?**
A: Don't assume one root cause explains every symptom on a shared dashboard — gather independent evidence for each symptom (here: a cache stat and a per-host LB stat) and verify each fix against its own symptom before declaring the incident resolved.
**Key point**: "One incident ticket does not mean one failure — verify every distinct symptom against its own evidence."

## STATUS: PASS
