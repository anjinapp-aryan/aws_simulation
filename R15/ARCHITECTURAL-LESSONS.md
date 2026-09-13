# R15 — Architectural Lessons (consolidated, evidence-grounded)

1. **Connection-pool sizing must account for worst-case dependency latency**, not steady-state (INCIDENT-01).
2. **A single infrastructure event can present as multiple, seemingly unrelated tickets** — check for a shared timing correlation before triaging as separate incidents (INCIDENT-02).
3. **CDC/replication connectors must be leader-aware, not pinned to a specific node hostname** — a real HA failover otherwise breaks an unrelated pipeline (INCIDENT-02).
4. **Recreating a Kafka Connect connector allocates a fresh replication slot** — this silently drops any commits between the old connector's failure and the new one's creation; a reconciliation process independent of connector health is needed (INCIDENT-02, unplanned finding).
5. **Don't declare an incident resolved after the first fix works** — verify every distinct symptom against its own independent evidence; two symptoms on one dashboard are not proof of one cause (INCIDENT-03).
6. **A dependency's own health does not guarantee every caller has recovered** — but this is a property of the caller's own architecture (stateless request handling + a pool that detects dead backends), not a universal law; test it, don't assume it either way (INCIDENT-04).
7. **The loudest alert is not always the root cause** — an un-backed-off client retry loop can convert a quiet backend failure into a loud, resource-visible symptom; trace what's generating load before scaling to absorb it (INCIDENT-05).
8. **Client-side retry logic needs its own backpressure/circuit-breaking** — server-side circuit breaking (Envoy/R9) does not protect against a client retrying against a dependency that isn't actually progressing (INCIDENT-05).
9. **An untested backup is not a backup** — verify DR readiness (WAL-archive continuity, `pgbackrest info`'s own status) on a schedule, independent of whether the configuration "looks right" (INCIDENT-06, and independently, R14 Experiment 7's Velero/hostPath finding — the same lesson surfacing twice via two unrelated mechanisms).
10. **A tool that fails loudly when misconfigured is safer than one that fails silently** — pgBackRest's own real 60s-timeout-then-error behavior when WAL archiving is broken is a genuinely good design property, discovered by running it for real (INCIDENT-06).
