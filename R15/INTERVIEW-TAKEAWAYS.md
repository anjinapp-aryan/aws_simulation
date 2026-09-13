# R15 — Interview Takeaways (per incident, real-execution-confirmed)

**Q: How do you troubleshoot an API latency spike?**
A: Check golden signals, then correlate traces against the dependency chain rather than guessing. (INCIDENT-01: a trace's own span breakdown proved DB-read dominance, ruling out cache/queue/circuit-breaker without touching any of them.)
**Key point**: "A span breakdown is a hypothesis-eliminator, not just a slow-request finder."

**Q: How do you distinguish root cause from a cascading symptom?**
A: Check whether multiple tickets' timestamps trace to one shared underlying event before treating them as independent. (INCIDENT-02: checkout 5xx and stuck orders shared one root cause — a real Patroni failover.)
**Key point**: "Two tickets, one timestamp correlation — check before you triage them as two incidents."

**Q: How do you handle multiple simultaneous failures?**
A: Gather independent evidence for each symptom and verify each fix against its own symptom. (INCIDENT-03: a cache stat and a per-host LB stat were needed, separately, to fully resolve two coexisting faults.)
**Key point**: "One incident ticket does not mean one failure."

**Q: Does a healthy dependency mean the whole system has recovered?**
A: Not automatically — but don't assume failure either; test it. (INCIDENT-04: the hypothesis of an app-level recovery gap was tested and honestly disproven — PgBouncer's own reconnect behavior handled it transparently in this architecture.)
**Key point**: "Test the caller, don't just trust the callee — and don't assume the worst without evidence either."

**Q: How do retries create a retry storm, and how do you investigate one?**
A: An un-backed-off client retrying against a non-progressing dependency converts a quiet failure into a loud, resource-visible symptom. (INCIDENT-05: real Jaeger traces showed repeated identical retry spans; the real root cause was a silently `PAUSED` Kafka Connect connector, not the CPU itself.)
**Key point**: "The loudest alert is not always the root cause — trace what's generating the load."

**Q: How do you verify a backup is actually recoverable?**
A: Automate DR-readiness verification (WAL-archive continuity, backup tool status) — don't trust that a configuration "looks right." (INCIDENT-06: a one-character typo in `archive_command` produced zero valid backups for an unknown period, discovered only when a backup was actually attempted.)
**Key point**: "A backup you haven't tested is a hope, not a backup."

**Q: How do you decide recovery order in a multi-part incident?**
A: Fix the root cause before the amplifier, and verify the pipeline itself works before attempting to reconcile any data gap it may have caused. (INCIDENT-02/05: resume/repoint the broken dependency first; let dependent symptoms subside and verify independently, rather than acting on all fronts at once.)
**Key point**: "Recovery order follows the dependency graph, not the loudest alert."

**Q: How do you calculate MTTR/RTO in a real incident?**
A: From real, captured timestamps — fault-injection time to first-verified-recovery time — never estimated after the fact. This project's own measured numbers (INCIDENT-02: 46.5s, INCIDENT-04: 46.3s) independently confirmed the same underlying DCS-TTL mechanism across two separate incidents.
**Key point**: "If you can't point to the two timestamps you subtracted, you don't have an RTO — you have a guess."
