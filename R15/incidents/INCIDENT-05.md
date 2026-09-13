# INCIDENT-05 — CAPSTONE: Order Confirmations Delayed + CPU Alert (retry storm masks a silent connector pause)

**Severity**: SEV-1
**Business impact**: order confirmations delayed indefinitely; on-call also paged for elevated app-tier CPU.
**Initial symptoms**: TWO alerts fired close together — "order confirmation SLO breached" (quiet) and "order-service CPU elevated" (loud, alert-friendly).

## The trap
The CPU alert is the louder, more actionable-looking signal — the natural first instinct is to treat resource pressure as the incident and consider scaling out or investigating "why is this pod using so much CPU."

## Real evidence gathered, in the order a disciplined investigation should gather it
1. **Golden signals first**: `docker stats` showed real CPU jumping from a ~0.5-0.9% baseline to **7-8% during load** (`evidence/incident-05/timeline.txt`) — real, measured, roughly 8-15x — but this alone doesn't say *why*.
2. **Traces, not just metrics**: Jaeger (`evidence/incident-05/jaeger-retry-pattern.txt`) showed **repeated, near-identical `poll-confirmation-attempt` spans** (3 per trace, each ~8-15ms, each a real DB read) inside every `poll-confirmation` trace — this is the signature of a retry loop, not organic per-request load. This is the evidence that disproves "CPU pressure is the root cause" — the CPU is elevated *because of* retries, not because of raw traffic volume.
3. **Follow the dependency the retries are aimed at**: the retries are polling `/order-status` for a `CONFIRMED` state that never arrives. Checking `order-outbox-connector`'s own Kafka Connect REST status (`evidence/incident-05/connector-status.txt`) revealed **`state: PAUSED`** — a real, deliberately silent fault (no crash, no error in order-service's own logs, exactly R13-08's own finding, now nested one level deeper inside a second, amplifying failure).
4. **Confirm scope**: `outbox` table row count = 71 and growing — orders are being created correctly (the local transaction still works), they simply never get relayed.

## Root cause vs. contributing factor vs. secondary symptom (required separation)
- **ROOT CAUSE**: `order-outbox-connector` silently `PAUSED` via the Kafka Connect REST API.
- **CONTRIBUTING FACTOR**: the client's polling logic has no backoff/circuit-breaker of its own — every unconfirmed order gets retried at a fixed interval indefinitely (bounded to 3 attempts per call in this build, but called repeatedly by a real load pattern, which has the same amplifying effect as an unbounded retry in aggregate).
- **SECONDARY SYMPTOM**: the CPU alert — a real, measured effect, but not itself something a scale-out or CPU-focused fix would resolve, since the underlying confirmations would still never arrive.

## Mitigation vs. root-cause fix
**Mitigation** (applied, real): `PUT /connectors/order-outbox-connector/resume` — real, immediate; a previously-stuck order (`inc5-1`) confirmed within 20s of resume, with **zero data loss** (Debezium resumed from its paused WAL position, same mechanism proven in R13-08/R14).
**Root-cause fix** (proposed, not built): the client-side retry/poll logic should have its own backoff and a cap on total wall-clock retry duration, with an explicit "give up and surface an error" path — so a backend outage degrades gracefully into visible failures rather than invisible, resource-consuming retries.
**New failure mode this fix could introduce**: an overly aggressive backoff/cap could cause legitimate slow-but-eventually-successful confirmations to be prematurely reported as failed — the cap must be tuned against the pipeline's own real observed latency distribution (e.g., R11/R13's documented ~20-30s cold-consumer-group relay time), not an arbitrary number.

## Recovery ordering
1. Resume the connector (stops the root cause). 2. Let the amplifier (retries) naturally subside once confirmations start arriving (no separate action needed — verified, not assumed). 3. Verify a previously-stuck order confirms. **Why this order**: fixing the retry logic first without fixing the connector would still leave orders unconfirmed; scaling out CPU first would do nothing for either the root cause or the contributing factor.

## Verification
Independent, multi-signal: connector REST status (`RUNNING`), a specific previously-stuck order's real `CONFIRMED` status, and (implicitly) CPU returning to baseline once the retry storm's triggering condition (unconfirmed orders) resolved.

## Blast radius / architectural review
1. Why did the failure propagate into a CPU alert? An un-backed-off client retry loop converted a quiet backend pause into a loud, resource-visible symptom.
2. Blast radius: all orders placed during the pause window (71+), plus a real, measured CPU cost on both app replicas.
3. Where should backpressure/circuit-breaking exist? On the client's own retry logic (missing here, a genuine architectural gap, not previously exercised by R9's server-side circuit breaker) — R9/R13's Envoy-side circuit breaking protects against a failing *backend*; nothing in this stack protects against a client retrying against a *silently-not-progressing* dependency.
4. Was observability sufficient? The connector's own `PAUSED` state was directly queryable the whole time — the gap was investigative discipline (checking the loud alert first), not missing telemetry.

## AWS mapping
Local: order-service's own poll/retry loop amplifying a paused Kafka Connect connector into a CPU alert. AWS analog: a Lambda or ECS task's own retry policy amplifying a paused AWS DMS/MSK Connect task into a visible Lambda-duration/cost or ECS CPU-utilization alert — the same causal shape (misdirected root-causing via the loudest signal), a real, common AWS on-call pattern.

## Interview takeaway
**Q: How do retries create a retry storm, and how do you investigate one?**
A: An un-backed-off client retrying against a dependency that isn't actually progressing converts a quiet, silent backend failure into a loud, resource-visible symptom — investigate by tracing what the retries are actually retrying against (here, traces showed identical repeated spans polling for a status that never changes), not by treating the resource alert itself as the incident.
**Key point**: "The loudest alert is not always the root cause — trace what's generating the load before you scale to absorb it."

## STATUS: PASS
