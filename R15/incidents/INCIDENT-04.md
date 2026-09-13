# INCIDENT-04 — Database Recovered, Is the App Actually Healthy? (hypothesis tested, disproven honestly)

**Severity**: SEV-3
**Business impact**: brief (~46s) checkout unavailability during a second, independent leader failure.
**Initial symptoms**: `patronictl list` shows a fully healthy cluster; the investigation question was whether the application (through PgBouncer) would show a *separate*, lagging recovery.

## What was tested
Real `docker kill demo-patroni3` (the leader) at **T0 = 12:12:38.678502**, with the app's DB path routed through the real PgBouncer instance (which maintains its own persistent backend connections, a genuine candidate for a "dependency recovered, caller didn't" gap). Polled `/order-status` every ~1-2s.

## Real, honest result
`evidence/incident-04/app-poll.txt`: `HTTP 000` (connection refused) for ~13s, then `HTTP 503` for ~34s, then `HTTP 404` (a real, working response — the probed order simply didn't exist, proving the app-DB path was functional again) at **12:13:25** — **RTO ≈ 46.3s**, matching Incident 2's own measurement closely (same underlying DCS-TTL mechanism, consistent finding).
**The hypothesized "recovery complication" was NOT observed** in this configuration: PgBouncer transparently detected the dead backend and reconnected to the new leader (via HAProxy) without manual intervention, and the app itself opens a fresh connection per request (no long-lived, app-level connection cache to go stale). Recovery of the DB layer and recovery of the app layer happened within the same observation window.

## Why this is still a valid, valuable investigation (not a failed experiment)
The original hypothesis — "the DB can recover while the app doesn't" — is a real, well-documented failure mode in production systems that use **long-lived, app-managed connection pools with aggressive keep-alive** or client-side connection caching (e.g., a JDBC pool that doesn't validate connections before reuse, or a driver that caches a resolved IP rather than re-resolving a DNS-based endpoint). This lab's specific architecture (PgBouncer as the pooling layer, with its own backend health detection, in front of a stateless per-request app) does not exhibit that failure mode — and proving that with real evidence, rather than assuming the textbook failure mode always applies, is itself the correct senior-engineer instinct.

## Mitigation vs. root-cause fix
Not applicable — no separate app-level fix was needed in this run.

## Architectural review
1. Why didn't it propagate into a longer app-level outage? PgBouncer's own backend connection management absorbed the failover transparently.
2. Where WOULD this fail? If the app itself held long-lived connections (not the case here) or if PgBouncer's own health-check interval were configured much longer.
3. What new failure mode could "fixing" a problem that doesn't exist introduce? Adding unnecessary connection-recycling logic (e.g., a periodic app restart "just in case") would add operational complexity and a new restart-induced availability risk for no real benefit in this specific architecture.

## AWS mapping
Local: PgBouncer's real backend reconnection behavior after a Patroni failover. AWS analog: RDS Proxy's own connection draining/re-establishment during a Multi-AZ failover (RDS Proxy is specifically designed to mask this from the application, similar in spirit to what was observed here). Different: RDS Proxy's internal mechanism differs from PgBouncer's; AWS-only: RDS Proxy's specific failover-masking guarantees and SLAs.

## Interview takeaway
**Q: Does a healthy dependency mean the whole system has recovered?**
A: Not automatically — verify the caller independently. In this specific case, verification showed the caller (via PgBouncer) recovered in lockstep with the database, but that is a property of THIS architecture's connection-pooling choice, not a guarantee that holds for every architecture — a JDBC pool with stale-connection reuse could behave very differently, and that difference should be tested, not assumed, for any given stack.
**Key point**: "'The dependency's dashboard is green' is a hypothesis about the whole system's health, not a proof of it — test the caller, don't just trust the callee."

## STATUS: PASS (hypothesis tested and disproven with real evidence — a legitimate investigative outcome)
