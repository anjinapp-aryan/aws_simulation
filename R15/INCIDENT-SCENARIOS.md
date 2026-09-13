# R15 — Incident Scenarios (design document — root causes are hidden from the investigator at execution time; this document is the answer key)

## R15-01 — "Checkout is slow" (LEVEL 1: single hidden fault, multiple signals)
**Business impact**: checkout p95 latency up, some customers abandoning.
**Initial symptom**: `/checkout` p95 latency 100ms → 3s. Error rate normal.
**Observable signals**: Grafana (latency panel), Jaeger (span breakdown), pgweb (connection count), Envoy admin (unaffected — rules out circuit breaker).
**Fault injected**: Toxiproxy DB latency (400ms) + deliberately small PgBouncer/connection-pool sizing (R13-01 mechanism, now inside the standing system where cache and queue are ALSO live and must be ruled out first).
**Hidden root cause**: DB connection-pool queueing amplifying moderate DB latency (same class as R13-01, now requiring the investigator to first rule out cache and queue as red herrings since they're live in the same system).
**Secondary effects**: none (single-hop).
**Misleading signal**: cache hit-ratio panel looks fine (tempts "check cache first" — a dead end here, unlike R15-03).
**Expected investigation difficulty**: Low-Medium (R13-trained investigator should recognize the pattern, but now must actively rule out 2 extra live subsystems first).
**Required evidence**: Jaeger span dominance, pool-size config, before/after latency.
**Recovery objective**: remove toxic, verify latency recovery.
**R1-R14 mechanisms reused**: R4/R13 (Toxiproxy+pool), R8 (Jaeger).
**Architectural lesson**: connection-pool sizing must account for worst-case dependency latency, not steady-state.

## R15-02 — "Orders stuck AND checkout erroring" (LEVEL 2: one root cause, cascading cross-subsystem symptoms)
**Business impact**: some checkouts fail outright (5xx); separately, confirmed orders aren't flipping to CONFIRMED.
**Initial symptom**: TWO seemingly unrelated tickets — "checkout 5xx spike" and "order confirmation backlog" — filed around the same time.
**Observable signals**: Grafana error-rate (app), Kafka UI (consumer lag climbing on `outbox.event.Payment`), `patronictl list` (shows a recent leader change), Dozzle (app logs show DB connection errors right at the same timestamp as the Kafka lag starts).
**Fault injected**: real `docker kill` on the Patroni leader (R14 mechanism) — a genuine automatic failover occurs.
**Hidden root cause**: the failover itself (~26s real Patroni RTO, per R14) causes a burst of connection errors in BOTH the checkout app (5xx) AND the payment-service's Kafka consumer thread (which holds its own DB connection and doesn't automatically retry cleanly) — ONE root cause (the failover), TWO seemingly independent-looking symptom tickets.
**Secondary effects**: Kafka consumer lag continues to climb for longer than the failover itself took, because the consumer's own reconnect logic is slower than HAProxy's re-routing.
**Misleading signal**: the two tickets' timestamps are close but not identical (app 5xx stops almost immediately once HAProxy re-routes; consumer lag keeps climbing for another 30-60s) — tempts investigators to treat them as two separate incidents.
**Expected investigation difficulty**: Medium — requires correlating two different dashboards' timestamps against `patronictl`'s own failover history to realize they share one cause.
**Required evidence**: `patronictl list` timeline/history, Kafka UI lag graph, app error timestamps, all aligned.
**Recovery objective**: confirm the new leader is stable; verify consumer catches up on its own (or needs a restart, discovered live — a real, not scripted, outcome).
**R1-R14 mechanisms reused**: R14 (Patroni failover), R11/R13 (Kafka consumer/outbox).
**Architectural lesson**: a single infrastructure event can present as multiple, seemingly unrelated tickets — incident triage should check for a shared timing correlation before treating tickets as independent.

## R15-03 — "Reads are slow AND some reads fail" (LEVEL 3: two independent, simultaneously active faults)
**Business impact**: product page reads slow for everyone; a subset of requests fail outright.
**Initial symptom**: elevated read latency across the board, PLUS a smaller number of hard failures.
**Observable signals**: Grafana (latency AND error-rate both elevated, on the SAME dashboard, tempting a single-cause assumption), Valkey `INFO stats` (hit ratio collapsed), Envoy admin (one app replica ejected as an outlier).
**Fault injected TWO, independent**: (1) Valkey `maxmemory` set too low (R13-07 mechanism) causing universal cache-miss/slow-read latency; (2) SEPARATELY, a Toxiproxy timeout on one app replica's DB path (R13-02/R9 mechanism) causing Envoy to eject that replica, which accounts for the hard-failure subset.
**Hidden root cause**: TWO unrelated root causes active at once — fixing only one leaves the other symptom unresolved, which is itself the intended lesson.
**Secondary effects**: none beyond the two faults' own direct effects (deliberately — this scenario tests whether the investigator correctly attributes each symptom to its OWN cause rather than assuming one fix resolves everything).
**Misleading signal**: both symptoms appearing on the same Grafana panel at the same time strongly suggests one cause; only Envoy's per-host ejection stats and Valkey's own hit-ratio stat can separate them.
**Expected investigation difficulty**: Medium-High — the trap is stopping investigation after finding the first (cache) cause and assuming the error-rate symptom will resolve too.
**Required evidence**: Valkey hit-ratio stat (proves cache cause), Envoy ejection stats naming a specific host (proves the second, separate cause).
**Recovery objective**: BOTH must be fixed and BOTH must be independently re-verified.
**R1-R14 mechanisms reused**: R6/R13 (Valkey), R9/R13 (Envoy).
**Architectural lesson**: don't declare an incident resolved because the first fix you found worked — verify every distinct symptom against its own evidence.

## R15-04 — "Database recovered but the app is still broken" (LEVEL 4: failure + recovery complication)
**Business impact**: checkout still failing 5+ minutes after the DB team confirms the database is healthy.
**Initial symptom**: `patronictl list` shows a fully healthy cluster (new leader stable, replicas streaming), yet the app is still returning `DB_ERROR`.
**Observable signals**: `patronictl list` (healthy), Grafana (app error rate still elevated, NOT recovering despite DB health), Dozzle (app logs show connection errors referencing the OLD leader's IP).
**Fault injected**: real Patroni failover (same mechanism as R15-02), but this time the app's own long-lived `psycopg2` connections (or an app-level DNS/connection cache, depending on implementation) don't get torn down and recreated against the new leader automatically.
**Hidden root cause**: the DB layer recovered correctly (real, verified); the RECOVERY COMPLICATION is entirely in the application's own connection-reuse behavior, not the database.
**Secondary effects**: none (this is deliberately a "one thing recovered, a second thing didn't" scenario, not a cascade).
**Misleading signal**: `patronictl list`'s all-healthy status strongly suggests the incident should already be over — tempts a "must be a monitoring lag, wait and see" non-action.
**Expected investigation difficulty**: Medium — requires the insight that "the dependency is healthy" and "the caller has recovered" are two separate facts to verify independently.
**Required evidence**: `patronictl list` healthy timestamp vs. continued app error timestamps; app log showing stale connection target.
**Recovery objective**: restart/recycle the app's connections (real fix); verify error rate actually drops afterward.
**R1-R14 mechanisms reused**: R14 (Patroni failover).
**Architectural lesson**: a dependency's own health check passing does not guarantee every caller has actually recovered — connection pooling/caching layers can silently outlive the failure they were built to survive.

## R15-05 — "Confirmations delayed, and CPU is spiking" (LEVEL 5 CAPSTONE: multi-effect incident with a misleading signal)
**Business impact**: order confirmations delayed by minutes; on-call also sees CPU alerts on one app replica.
**Initial symptom**: two alerts fire close together — "order confirmation latency SLO breached" and "app-replica-2 CPU >90%".
**Observable signals**: Grafana (CPU spike on one replica — looks like the obvious lead), Kafka Connect REST (`GET /connectors/.../status` — NOT checked by default, must be thought of), Jaeger (shows retry storms — repeated identical spans), Dozzle (app logs show a rapidly repeating retry loop against the payment confirmation path).
**Fault injected TWO, related but distinct**: (1) the `order-outbox-connector` is silently `PAUSED` (R13-08/R11 mechanism — orders never get their outbox event relayed); (2) the app has an aggressive, unbounded retry policy on "check payment status," so once confirmations stop arriving, retries pile up and consume real CPU on the replica handling them.
**Hidden root cause**: the paused Kafka Connect connector (fault #1) is the true root cause; the CPU spike (fault #2's effect) is a SECONDARY SYMPTOM caused by the app's own retry-amplification of fault #1 — not an independent root cause, and NOT fixable by "add more replicas" or "reduce CPU pressure," which is the tempting-but-wrong mitigation.
**Secondary effects**: retry-amplification is itself a real, separate architectural finding (unbounded retries turning a silent backend issue into a visible resource-pressure alert).
**Misleading signal**: the CPU alert is louder and more "actionable-looking" than the quieter SLO breach, tempting the investigator to treat CPU pressure as the incident, scale out, and declare victory while the connector stays paused and orders keep failing to confirm.
**Expected investigation difficulty**: High — requires resisting the most visible alert and tracing the retry storm back to what it's retrying against.
**Required evidence**: Jaeger's repeated identical spans (proves retry storm, not organic load), Kafka Connect REST status (`PAUSED`, the real root cause), outbox table row growth (R13-08's own evidence pattern), CPU graph correlated to retry rate rather than request rate.
**Recovery objective**: resume the connector (real fix); separately decide whether to also bound the retry policy (architectural improvement, not just incident mitigation) — and explicitly reason about what NEW failure mode a naive fix (e.g., "just add a longer timeout") could introduce.
**R1-R14 mechanisms reused**: R11/R13 (Kafka Connect pause/outbox), R8/R13 (Jaeger retry-storm evidence), new-but-thin: an app-side retry loop (a few lines, justified — no existing R-lab has one).
**Architectural lesson**: the loudest signal is not always the root cause; unbounded retries can convert a quiet backend failure into a loud resource-pressure alert, misdirecting the investigation and masking the real fix.

## R15-06 — "The backup exists, but recovery is failing" (BONUS: backup/DR failure discovered mid-incident)
**Business impact**: during an unrelated DB incident, the on-call engineer reaches for the documented recovery path (restore from backup) and discovers it doesn't actually work.
**Initial symptom**: a real, separate DB problem (e.g., R15-01's own latency fault, escalated) leads the investigator to attempt a precautionary/actual restore; `pgbackrest restore` fails or restores stale data.
**Observable signals**: `pgbackrest info` (shows the last successful FULL backup is much older than expected, or WAL archiving has silently been failing).
**Fault injected**: `archive_command` silently misconfigured/broken some time before the "incident" (e.g., pointing at a now-removed path) — mirroring R14 Experiment 5's own real WAL-archiving-gap finding, but now discovered reactively during a live incident instead of via a planned experiment.
**Hidden root cause**: the backup/DR mechanism itself had a latent, undetected gap — the "incident" is really two: the original DB issue, AND the discovery that the safety net was already broken.
**Secondary effects**: none beyond the panic of discovering DR doesn't work when needed.
**Misleading signal**: `pgbackrest info` initially looks fine at a glance (a backup exists) — only checking its actual timestamp/WAL-archive continuity reveals the gap.
**Expected investigation difficulty**: Medium — requires the discipline of checking DR readiness, not just DR existence.
**Required evidence**: `pgbackrest info` timestamps, WAL archive continuity check.
**Recovery objective**: recover via whatever path is actually available (live replica if one exists); separately, fix and re-verify the backup mechanism itself.
**R1-R14 mechanisms reused**: R14 (pgBackRest, its own real Experiment 5 finding now repurposed as a hidden fault).
**Architectural lesson**: an untested backup is not a backup — DR readiness must be periodically verified, not assumed from "a backup command exists in the runbook."

## Coverage summary against the requested success criteria
- Cascading failure: R15-02.
- Multi-failure (independent): R15-03.
- Failure + recovery complication: R15-04.
- Misleading signal + retry amplification: R15-05.
- Backup/DR failure discovered mid-incident: R15-06.
- Progressive difficulty Level 1→5: R15-01 through R15-05, R15-06 as an unleveled bonus.
