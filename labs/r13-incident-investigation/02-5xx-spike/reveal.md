# R13-02 — SPOILER — ROOT CAUSE

## What was injected
`inject.sh` set a real Toxiproxy `timeout` toxic (2000ms) on `app2`'s **own** DB path (the `db2` proxy) — `app1`'s DB path (`db` proxy) is untouched. `app2` uses `/order-raw` (unprotected — no app-level circuit breaker), so its failures are visible directly to Envoy.

## Real observed evidence
- Client-visible result over 100 requests through Envoy: **94×200, 6×500** (`evidence/lb-results.txt`).
- Per-replica request counts from container logs: **app1 received 96 requests, app2 received only 7** (`docker compose logs app1/app2`) — a massive, non-random skew from the expected ~50/50 round robin.
- Envoy's own outlier-detection stats (`evidence/envoy-outlier-stats.txt`): `ejections_enforced_total: 2`, `ejections_enforced_consecutive_5xx: 2`.
- Envoy's live cluster state (`evidence/envoy-clusters-app2.txt`): app2's endpoint shows `health_flags::/failed_outlier_check` — Envoy itself, not app2, marked it unhealthy.

## Root cause
`app2`'s dependency (its DB path) is genuinely broken (2s timeout toxic). Without any protection this would produce roughly 50% client-visible failures (half the round-robin traffic hits the broken replica). Instead only 6% failed, because Envoy's real `outlier_detection` (`consecutive_5xx: 3`, configured in R9 and reused unmodified here) detected 3 consecutive 5xx from app2, ejected it from the load-balancing pool for `base_ejection_time: 10s`, and re-tried it periodically — each retry that still fails re-ejects it, so app2 receives only a handful of "probe" requests over the whole run instead of half of all traffic. **The 5xx spike is real, but it is self-limiting because of Envoy's own outlier detection** — the investigator's job was to notice the skewed per-host traffic distribution and Envoy's own ejection stats, not to assume every replica is equally broken.

This is the direct, intended contrast with R9's own finding (single-replica clusters hit Envoy's panic threshold and ejection has zero effect) — with **2 real replicas**, ejection has a large, measurable effect.

## Immediate mitigation
Fix app2's DB path (remove the toxic) — `fix.sh`.

## Permanent fix / prevention
- Alert on Envoy's `ejections_enforced_total` / per-host `health_flags` directly — it is the earliest, most precise signal (available before the aggregate error-rate crosses a human-visible threshold).
- Root-cause app2's actual dependency (its DB connection) rather than relying on ejection alone — ejection reduces blast radius, it doesn't fix the underlying broken replica, which stays fully unavailable to any client whose request does land on it during a probe window.

## AWS mapping
ALB/NLB target-group health checks (or App Mesh/Envoy-based ECS service mesh outlier detection) automatically routing around one unhealthy target while the ASG's health-check-triggered replacement catches up — the real mechanism this maps to, not a simulation of it.
