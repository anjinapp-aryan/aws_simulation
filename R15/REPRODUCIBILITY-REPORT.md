# R14/R15 REPRODUCIBILITY — FINAL REPORT

## 1. Status

**PASS.** Cold start, second run, idempotent re-run, existing-incident regression, and visualization checks all executed live and all passed. Two real bugs were found during the work and fixed.

## 2. Gap Closed

R15 was proven but not restartable. Evidence gathered in the preceding audit: zero shell scripts in `labs/r15-capstone/`, no learner-facing README in `R15/` or the lab directory, and none of R15's 17 documents contained a single `docker build` or `docker compose up` line. Its two Debezium connector JSON files were referenced by no script and no document anywhere in the repository. R15 additionally requires an external network provided by R14, and R14's own only documented start command (`EXPERIMENT-RESULTS.md:9`) fails outright with `pull access denied for patroni` because the image must be built first.

Six undocumented steps stood between a clean machine and R15's own documented baseline.

## 3. Before vs After

**Before** — manual archaeology across 17 documents; undocumented cross-stack prerequisite; a start command that fails as written; manual image build; manual Toxiproxy proxy creation; manual connector registration; manual `wal_level` reconfiguration; no way to confirm the environment actually worked.

**After** — one documented command (`./scripts/run.sh`) handles every prerequisite in order; one command (`./scripts/verify.sh`) proves real end-to-end behaviour with 13 assertions; `status.sh` gives a read-only picture; `cleanup.sh` is the only destructive path; `R15/README.md` carries the full learner journey and `R14/README.md` makes R14 a reliable prerequisite.

## 4. GitHub Reuse Audit

| Component | Repository | License | Decision | Reason |
|---|---|---|---|---|
| Script conventions (`run`/`status`/`verify`/`cleanup`) | this repo, R2–R13 (esp. R11) | n/a | **REUSE** | Proven across 11 phases; zero new dependency; R15 already reuses R11's architecture |
| Toxiproxy control API usage | this repo, R11 `run.sh` | MIT (Toxiproxy) | **REUSE** | Exact existing pattern, extended to R15's three proxies |
| Kafka Connect REST registration | this repo, R11 `run.sh` | Apache-2.0 (Debezium) | **ADAPT** | Added idempotency and task-state waiting; R11's version assumes a clean start |
| Patroni REST `PATCH /config` + `patronictl` | `patroni/patroni` (vendored) | MIT | **REUSE** | Patroni's own persistent configuration mechanism; avoids editing the vendored official repo |
| `go-task/task` (Taskfile) | go-task/task | MIT | **REJECT** | New binary install on Windows; breaks consistency with 13 phases; adds no learning value |
| `casey/just` | casey/just | CC0 | **REJECT** | Same — new dependency for no gain |
| `make` | GNU | GPL | **REJECT** | Not reliably present in this Git Bash environment |
| Compose native `include:` | Docker Compose v5.1.4 | Apache-2.0 | **REJECT (evaluated)** | Verified available, but R15's dependency on R14 is not just file composition — it needs ordered readiness gating, a leader switchover and a rolling restart between the two stacks. `include:` cannot express that, so it would have added a mechanism without removing one. |

No purpose-built tool exists for "reproducible multi-stack lab runbook"; the repository's own convention was the strongest available reuse.

## 5. Existing Repository Patterns Reused

R11's four-script layout and its Toxiproxy/Debezium bootstrap sequence; R13's README structure (symptom-first framing, per-scenario table, explicit troubleshooting section); R14's own REST-based Patroni reconfiguration technique from Experiment 5; the repository's `.gitattributes` LF enforcement for all new shell scripts.

## 6. Files Added

- `labs/r15-capstone/scripts/run.sh` — reproducible startup, idempotent, bounded waits
- `labs/r15-capstone/scripts/verify.sh` — 13 real end-to-end assertions
- `labs/r15-capstone/scripts/status.sh` — read-only snapshot
- `labs/r15-capstone/scripts/cleanup.sh` — the only destructive path (`--all` also removes the R14 foundation)
- `labs/r15-capstone/evidence/reproducibility/` — cold-start, second-run, idempotency and incident-regression logs
- `R15/README.md` — learner journey
- `R14/README.md` — minimum runbook making R14 a reliable prerequisite

## 7. Files Modified

**None.** `git status` shows zero modified tracked files — only the new paths above. R1–R13, R10's Headlamp integration, R14's metrics visualization, and every R15 incident, experiment conclusion and measured RTO/RPO value are untouched.

## 8. Final Architecture

```
labs/r15-capstone/scripts/run.sh
   |
   +-- builds image `patroni`            (if absent)
   +-- starts R14: patroni-src compose   -> network patroni-src_demo, 3-node HA cluster
   +-- ensures patroni1 is leader        (real patronictl switchover if not)
   +-- ensures wal_level=logical         (Patroni REST PATCH /config + rolling restart)
   +-- starts R15 infrastructure         (toxiproxy, valkey, kafka, payment-db, pgbouncer)
   +-- creates proxies                   (orderdb 56000, orderdb2 56010, cache 56001)
   +-- starts R15 applications           (order-service x2, payment-service, Envoy, UIs)
   +-- registers Debezium connectors     (waits for connector AND task = RUNNING)
```

R15 joins R14's real cluster; the Patroni environment is never duplicated.

## 9. Startup Flow

Every wait is a real readiness condition with a bounded timeout and a diagnostic on failure — no blind sleeps. Readiness signals used: Patroni's own `/cluster` REST view, `SHOW wal_level`, Toxiproxy's control API, Envoy's own `/clusters` health flags, the app's `/health` through Envoy, and Kafka Connect's connector **and task** state.

Idempotency is per-step: the image build, `wal_level` change, proxy creation and connector registration are each skipped when already satisfied. `run.sh` never performs `docker compose down -v`.

## 10. Verification Flow

`verify.sh` asserts, and exits non-zero on any failure: 3 Patroni members healthy · leader identified · 2 replicas streaming · `patroni1` holds the leader role · `wal_level=logical` · PostgreSQL reachable · order-service healthy through Envoy · 2 healthy Envoy endpoints · both connectors `RUNNING` (connector + task) · order `CREATED` · Saga `CREATED → CONFIRMED` via the real CDC relay · cache-aside `db` then `cache`.

## 11. Cold-Start Evidence

Starting state (verified): no `patroni` image, no `patroni-src_demo` network, no containers.

Only `./scripts/run.sh` was executed — no manual build, no manual connector registration, no hidden configuration.

```
building image 'patroni' from the official patroni/patroni Dockerfile...
waiting for Patroni cluster to elect a leader (timeout 120s).. ok (4s)
waiting for all 3 Patroni members healthy (timeout 120s)..... ok (10s)
Patroni leader: patroni3
=== Switching leader to patroni1 (required by the pinned order connector) ===
waiting for patroni1 to become leader (timeout 90s) ok (0s)
wal_level is 'replica' - setting logical via Patroni REST PATCH /config
wal_level now: logical
proxy 'orderdb' created / 'orderdb2' created / 'cache' created
waiting for both order-service replicas healthy in Envoy (timeout 150s)....... ok (54s)
connector 'order-outbox-connector' registered / 'payment-outbox-connector' registered
waiting for order-outbox-connector RUNNING (connector + task) ok (2s)
```

Then `./scripts/verify.sh` → **PASSED: 13   FAILED: 0**.

This run independently validated the leader-switchover design: the fresh cluster elected **patroni3**, not `patroni1`, confirming election is genuinely non-deterministic and that a pinned connector would otherwise have failed.

Logs: `labs/r15-capstone/evidence/reproducibility/cold-start.log`, `cold-start-verify.log`.

## 12. Second-Run Evidence

`cleanup.sh --all` → `run.sh` → `verify.sh` → **PASSED: 13   FAILED: 0**. This run elected `patroni1` directly (no switchover needed), exercising the other branch. Logs: `second-run.log`, `second-run-verify.log`.

Idempotency separately tested by re-running `run.sh` against the live environment: every step reported `already present` / `already exists` / `already registered` / `skipping reconfiguration`, and a pre-existing order (`verify-1789403982`) was still `CONFIRMED` afterwards — no data destroyed. Log: `idempotency.log`.

## 13. Visualization Evidence

All existing UIs confirmed serving live: Kafka UI `59180`, Jaeger `59686`, Envoy admin `59901`, Grafana `59300`, pgweb `59081`/`59082`, Dozzle `59888`, Toxiproxy `59474`. R14's own stacks were also re-validated against the new `R14/README.md`: app `58500` HTTP 200, pgweb `58501` 200, Dozzle `58502` 200, Prometheus `58503` 302 (its normal redirect), Grafana `58504` 200, and the R14 metrics dashboard still provisioned with all 5 panels. No new UI was built.

## 14. Existing Incident Regression

INCIDENT-01 re-run using its documented mechanism unchanged (real 400ms Toxiproxy latency toxic on the `orderdb` proxy).

- **Baseline**: 8.7–17.0 ms across 5 reads (matches the incident's documented ~10 ms baseline).
- **T0 = 16:47:32Z, fault injected**: latency became bimodal — 13–16 ms on the unaffected path, **2.02 s** on `order-service-1`'s poisoned path, consistently.
- **Evidence eliminating competing hypotheses**: Envoy reported 2 healthy endpoints (not a replica failure); the order connector stayed `RUNNING` (not a CDC problem); `orderdb` showed the toxic while `orderdb2` showed none — isolating one replica's database path.
- **T3 = 16:47:59Z, documented mitigation applied** (toxic removed): all 8 reads returned to 13.1–16.2 ms, matching baseline.
- **Post-incident**: `verify.sh` → **13/13 PASS**, no residue.

The reproducibility work did not alter the incident's mechanism, symptom, investigation path or recovery. Log: `incident-01-regression.log`.

## 15. Bugs Found

**Bug 1 — a healthy Patroni replica never satisfies a `state == running` check.**
*Symptom*: cold start failed at `cluster healthy after restart did not become ready within 120s`, while `patronictl list` simultaneously showed a perfectly healthy cluster.
*Evidence*: Patroni's `/cluster` REST output showed `patroni1` as `"state": "running"` (leader) but `patroni2`/`patroni3` as `"state": "streaming"`.
*Root cause*: Patroni reports `running` for a leader and for a replica only briefly at startup; once replication is established a healthy replica reports `streaming`. The initial check passed at first boot purely because replication had not yet established — the same check would also have broken every idempotent re-run.
*Fix*: count both `running` and `streaming` as healthy, in `run.sh` and `verify.sh`. Also fixed the weak diagnostic that made this hard to see: a bare test expression produces no output, so `wait_for` now accepts an explicit diagnostic command and dumps `patronictl list` on timeout.
*Verification*: cold start and second run both reached 3/3 healthy members; `verify.sh` reports `3 Patroni members healthy` / `2 replicas streaming`.

**Bug 2 — a healthy replica can stay flagged `/failed_active_hc` in Envoy for up to a minute after startup.**
*Symptom*: immediately after startup, `verify.sh` reported only 1 of 2 healthy Envoy endpoints, while the "unhealthy" replica's own logs showed it serving HTTP 200s and processing Kafka events normally.
*Evidence*: Envoy admin showed `order-service-1 ... health_flags::/failed_active_hc` with cluster stats `health_check.attempt: 2, success: 1, network_failure: 1` — frozen at 2 attempts despite a configured 2 s interval, then jumping to `attempt: 6, success: 5` with both endpoints healthy about a minute later.
*Root cause*: order-service takes ~2 s to initialise its schema, so Envoy's very first health check can land while it is still starting and record a `network_failure`. Envoy then applies its default `no_traffic_interval` (60 s) to an idle cluster rather than the configured 2 s interval, so the replica stays flagged far longer than the health-check config suggests. Not a defect in the lab and not in the app — a real readiness race.
*Fix*: `run.sh` now gates startup on both endpoints being healthy in Envoy's own view, and deliberately curls `/health` inside that wait — real cluster traffic keeps Envoy on its normal interval instead of the idle one. `envoy.yaml` was **not** modified.
*Verification*: observed resolving in 54 s on both the cold start and the second run, after which `verify.sh` reported 2 healthy endpoints on the first attempt every time.

## 16. AWS Mapping

**REAL LOCAL BEHAVIOUR**: Patroni leader election, switchover and failover; PostgreSQL logical replication and replication slots; Debezium CDC; Kafka delivery; Envoy active health checking and outlier ejection; cache-aside semantics; Toxiproxy network faults.

**BEHAVIOUR-EQUIVALENT**: the shape of an RDS Multi-AZ failover, an MSK-backed event pipeline, and an ALB target-group health-check rotation — same class of behaviour, different implementation and timing.

**NOT REPRODUCED**: AWS control plane, real VPC networking, IAM, CloudWatch metrics/alarms, and RDS Multi-AZ's synchronous replication guarantee (this cluster is async by default — R14 measured real data loss because of it). Local Patroni is not RDS; local Kafka is not MSK; local Grafana is not CloudWatch.

## 17. $0 Validation

AWS resources: 0. AWS credentials: 0. Paid SaaS: 0. Cloud dependencies: 0. Subscriptions: 0. No new image or dependency was introduced — every container was already part of R14/R15. Everything runs locally on Docker.

## 18. Rollback

Delete the seven added paths listed in section 6. Because **no existing file was modified** (verified by `git status` showing zero modified tracked files), there is nothing to revert: removing the scripts and READMEs returns R14 and R15 to exactly their previous state, with every proven mechanism, experiment and measured result intact. The scripts only orchestrate — they are not a runtime dependency of anything.

## 19. Learning Impact

The capstone is now re-enterable. A learner returning after months opens `R15/README.md`, runs one command, gets a verified environment, opens the existing UIs, injects an existing incident, investigates it, recovers, and verifies — the full journey, without archaeology. The README deliberately explains *why* each prerequisite exists (the pinned connector, logical replication, the proxy topology) rather than hiding them behind automation, so the startup script teaches the architecture instead of concealing it.

## 20. Senior Architect Interview Takeaway

"A system that only one person can start, once, is not a system — it is a demo. We had six real production incidents with measured RTO and RPO, and none of it was re-enterable because the startup path lived in prose across seventeen documents. Making it reproducible found two real problems that no amount of documentation would have: a healthy Postgres replica reports `streaming`, not `running`, so the obvious health check is wrong in a way that only shows up on a *second* start; and a replica can sit flagged unhealthy in the load balancer for a full minute after it is already serving, because an idle cluster falls back to a 60-second health-check interval nobody configured. Both are the kind of thing you discover by actually restarting the system from zero — twice — and neither would have been found by reading the config."
