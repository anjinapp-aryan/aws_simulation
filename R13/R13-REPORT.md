# R13 — Production Troubleshooting / Incident Investigation — Report

## 1. Objective
Move past mechanism-specific labs (R1-R12, each teaching one AWS-adjacent component in isolation) to the actual senior/architect interview skill: given only a production symptom, investigate across multiple real signals to find a root cause that was never announced in advance, using nothing but tools a real on-call engineer would have.

## 2. Reuse decisions (full detail: `R13/REUSE-AUDIT.md`)
8 real GitHub searches across incident-simulator/troubleshooting-lab phrasings returned only 0-1★ unlicensed personal repos, except `open-telemetry/opentelemetry-demo` (3339★, Apache-2.0) — evaluated and marked **REFERENCE only** (adopting it would replace this project's own minimal app stack, violating the standing minimal-code/composition rules; its `flagd`-based fault injection is also feature-flag/in-process, whereas this project already has superior infrastructure-level fault primitives). **Decision: COMPOSE** — every R13 scenario reuses an existing R4/R6/R7/R9/R10/R11/R12 stack's real services and real fault-injection mechanisms (Toxiproxy, PgBouncer pool sizing, Envoy outlier detection, Valkey `CONFIG SET`, Kafka Connect REST pause/resume, K8s resource limits + `stress-ng`, Cilium NetworkPolicy) verbatim, composed under a new investigation harness (`inject.sh` / `investigate.md` / `reveal.md` / `fix.sh` per scenario — the only genuinely new code in this phase).

## 3. Architecture actually built
`labs/r13-incident-investigation/<01-08>/` — 8 self-contained scenarios, each a copy of an existing lab's `docker-compose.yml` (or `kind` manifests for 04/06) with host ports remapped to a dedicated range and one small, targeted composition addition where the incident needed it (e.g., a real DB write added to R7's consumer for the queue-backlog scenario; a second app replica behind Envoy for the 5xx scenario; a mislabeled "rollout" deployment for the network scenario). No new fault-injection mechanism, tracing SDK, cache, queue, database, or observability platform was built.

## 4. Experiments — all 8 executed for real against live containers/clusters, with captured evidence

### R13-01 High latency (reused R8's DB+cache+Jaeger+Grafana stack)
Toxiproxy 400ms DB latency + a deliberately small (`default_pool_size=5`) PgBouncer pool, under 30 concurrent `/checkout` requests. **Real result**: baseline 70ms → under fault avg 4.00s, max 6.04s (`evidence/load-results.txt`). Real Jaeger traces (`evidence/jaeger-traces.json`) proved the `db-query` span alone accounted for 99%+ of the 5.8-6.0s total, ruling out cache/queue. Root cause: connection-pool queueing amplifying a moderate DB latency into a severe one — PgBouncer's own client-wait time isn't a separate span, a genuine, honest observability blind spot. Fixed and verified: recovery to 75-77ms.

### R13-02 HTTP 5xx spike (reused R9's Envoy/PyBreaker stack, extended to 2 real replicas)
R9 itself found single-replica clusters hit Envoy's panic threshold, making outlier detection a no-op — R13-02 deliberately ran **2 real replicas**, each with its own Toxiproxy DB path, and broke only one (`app2`, via `/order-raw`, unprotected). **Real result**: 94/100 requests succeeded, only 6 failed — Envoy's real `ejections_enforced_total: 2` and `health_flags::/failed_outlier_check` (`evidence/envoy-outlier-stats.txt`) proved outlier detection genuinely ejected the bad replica after 3 consecutive 5xx, reducing customer-visible failure from what would be ~50% to 6%. Fixed and verified: 20/20 success, both replicas `healthy`.
**Real environment bug hit and fixed along the way**: Docker Desktop crashed mid-run (WSL2/npipe failure) — recovered via the project's standing restart procedure, plus the `docker-credential-desktop` config fix recurring after the restart. Also found and fixed a real sed-collateral-damage bug: a port-remap regex accidentally corrupted `DB_PORT: "6432"` into `"5832"` and `CACHE_PORT: "6379"` into `"5779"` in two scenario files — audited every scenario's env vars afterward and fixed both.

### R13-03 Queue backlog (reused R7's RabbitMQ stack, added one real DB write to the consumer)
Toxiproxy 800ms DB latency on the consumer's (newly-added) DB write path, then 60 messages published fast. **Real result**: RabbitMQ's own Management API showed `messages: 58`, ack rate 0.2/s vs. publish rate 2.6/s (`evidence/queue-during-incident.txt`) — proving the consumer was alive (`consumers: 1`) but merely slow, ruling out "consumer crashed." Consumer's own logs showed `db_write` jumping from 0.014s to 6.25-6.54s (an 8x multiplier over the 800ms toxic — consistent with this project's repeatedly-observed multi-round-trip latency compounding). Fixed and verified: backlog drained to 0.

### R13-04 Resource pressure (reused R10's exact OOMKill mechanism on a real `kind` cluster)
Real `stress-ng --vm-bytes 300M` inside one pod with a real `128Mi` memory limit. **Real result**: `kubectl describe pod` showed `Last State: Terminated, Reason: OOMKilled, Exit Code: 137, Restart Count: 1` on the same recurring pod name (not random). Fixed (self-healed automatically by Kubernetes) and verified: both pods `Running`, app serving normally.

### R13-05 Cascading failure (reused R11's Debezium/Kafka Saga stack)
Toxiproxy 800ms latency on **order-service's own** DB path only (Debezium's separate direct connection to `order-db` untouched). **Real result**: `payment-service` completed its payment in ~3s (on time, per its own logs); order-service's own confirmation write landed ~3.9s later, at 6.8s total (`evidence/poll.txt`) — proving the cascade was isolated to order-service's own DB write, not payment processing or CDC relay, contradicting the naive "whole Saga is slow" read. Fixed and verified: recovery to ~1.3s round trip.

### R13-06 Network/security failure (reused R12's exact Cilium/NetworkPolicy/Hubble stack on a real `kind` cluster)
A real second backend replica (`backend-v2`, sharing the `backend` Service via `app: backend`) deployed with a genuine label typo (`tier: backend-v2` instead of `tier: backend`). **Real result**: original backend pod → database `ALLOWED`; `backend-v2` → database `DENIED (timed out)` (`evidence/connectivity.txt`). Real Hubble flow data (`evidence/hubble-flows.txt`) proved DNS was fine (`EGRESS ALLOWED`/`FORWARDED`, ruling out the R12-07 failure mode) while the database path showed `policy-verdict:none EGRESS DENIED` / `Policy denied DROPPED (TCP Flags: SYN)`. Fixed (relabeled) and verified `ALLOWED (fixed)` — a stale-pod-selection artifact in the fix script (tested the old terminating pod first) was caught and corrected before declaring success.

### R13-07 Cache failure (reused R6's Valkey stack)
Real `CONFIG SET maxmemory 1mb` (below Valkey's own baseline footprint) + `allkeys-lru`, then 600 requests across 200 distinct keys. **Real result**: 600/600 MISS, 0 HIT (`evidence/hit-miss.txt`); `keyspace_hits:1, keyspace_misses:601`; `DBSIZE: 0` after the run — every cache write silently failed (the app's own documented fail-open `except Exception: pass` around `setex`), so every request paid full DB latency while still returning `200`, with nothing looking "down." Fixed (`maxmemory 256mb`) and verified: MISS→HIT working again, `DBSIZE: 1`.

### R13-08 Distributed transaction failure (reused R11's Debezium/Kafka Saga stack)
Real Kafka Connect REST `PUT /connectors/order-outbox-connector/pause` (a genuine connector state, not a crash). **Real result**: order-service's own logs showed nothing wrong (all `200`s — the intended trap); the `outbox` table genuinely grew (4 rows, confirming the local transaction/dual-write-problem fix still works); the connector's real REST status showed `PAUSED`; 3 orders stayed `CREATED` after a 15s wait. Fixed (`resume`) and verified: all 3 previously-stuck orders drained to `CONFIRMED` with **zero data loss** — Debezium resumed from its paused WAL position.

## 5. Real bugs found, root-caused, fixed (this phase's own investigation, on top of the designed incidents)
1. Windows Git-Bash `>>` file redirection from many backgrounded subshells silently lost most writes under real concurrent load (R13-01) — fixed by writing one file per process and concatenating.
2. A `sed`-based port-remap regex corrupted two non-port numeric env values (`DB_PORT`, `CACHE_PORT`) in two scenario compose files because they happened to start with the same two digits as the port prefix being replaced — caught by auditing every scenario's env vars after remapping, fixed both.
3. Docker Desktop crashed mid-run (`dockerDesktopLinuxEngine` pipe failure) — recovered via the project's already-standing restart procedure; the `docker-credential-desktop` config issue recurred after the restart and was fixed again the same way as prior phases.
4. Windows reserves dynamic TCP port ranges (`netsh interface ipv4 show excludedportrange`) that silently reject Docker host-port bindings — hit twice (54051-54250 excluded), root-caused via `netsh`, fixed by remapping to a free range (53xxx) rather than guessing.
5. Several scenario directories were missing supporting config dirs/files not caught by the initial `cp` (R7's `rabbitmq/` plugin config, R6's `sentinel/`/`traefik-dynamic.yml`, R11's `order-db/`/`payment-db/` init SQL) — each caused Docker to silently create an empty directory at the bind-mount target, masked as a 404 or connection error; root-caused by checking whether the mount target was a file or an empty directory, fixed by copying the missing source.
6. A stale-pod-selection artifact in R13-06's `fix.sh` tested the old (already-terminating) pod immediately after a rolling relabel, momentarily showing "STILL DENIED" — caught by re-querying for the new, Running pod specifically rather than accepting the first false negative.

None of these were hidden or silently patched — each is documented with the investigation that led to the real conclusion, per this project's standing rule.

## 6. Multi-signal correlation demonstrated
Every scenario required at least two independent real signals to reach the correct root cause, never a single dashboard: Grafana/latency + Jaeger spans (01), client success/failure + per-replica request counts + Envoy's own outlier stats (02), RabbitMQ ack/publish rates + consumer's own db_write timing (03), `kubectl describe` + pod-restart pattern across replicas (04), payment-service timestamps + order-service's own confirmation timestamp (05), pod labels + Hubble's own flow verdicts (06), cache hit/miss counters + `DBSIZE`/`used_memory` (07), order-service's clean logs (the trap) + outbox row count + Kafka Connect REST status (08).

## 7. REAL vs BEHAVIOR-EQUIVALENT vs NOT POSSIBLE LOCALLY
**REAL** (all 8): every fault is a genuine infrastructure-level condition (real Toxiproxy toxics, real PgBouncer pool limits, real Envoy outlier detection, real cgroup OOM kill, real Cilium policy enforcement, real Valkey memory config, real Kafka Connect connector lifecycle) and every diagnostic signal is real tool output, never scripted or asserted.
**NOT POSSIBLE LOCALLY**: correlating against a real paging system (PagerDuty/Opsgenie) and multi-week historical baselines for anomaly detection — out of scope, not attempted, consistent with the approved architecture.

## 8. Senior/Architect interview takeaways
- "Walk me through how you'd investigate a latency spike" — answered with a real, evidence-backed 8-scenario portfolio, not a memorized checklist: metrics → traces → logs → dependency → hypothesis → elimination → root cause, for 8 structurally different failure modes.
- "What's the difference between a service being down and being degraded?" — R13-07 and R13-08 are both genuinely "up" the whole time (no crash, no error), yet both are real incidents — a distinction only demonstrable, not describable, without having built and broken both.
- "How do you avoid tunnel vision on the first plausible cause?" — R13-02, R13-05, and R13-06 were each specifically designed so the obvious first guess (all replicas equally broken; payment is slow; DNS/network broadly down) was wrong, and only cross-signal correlation caught it.
- "What's a subtle production incident you've actually debugged?" — 8 real, reproducible stories with captured evidence, not hypotheticals.

## 9. $0 proof
Every image reused across all 8 scenarios is exactly the same free, official, already-proven-$0 image from R4/R6/R7/R9/R10/R11/R12 (Postgres, PgBouncer, Toxiproxy, RabbitMQ, Envoy, Valkey, Kafka, Debezium, Cilium, `kind`). No AWS credential referenced anywhere. No AWS API call made.

## 10. Cleanup proof
Every compose-based scenario (01, 02, 03, 05, 07, 08) torn down via `docker compose down -v`, verified via container-name grep returning empty. Both `kind`-based scenarios (04, 06) torn down via `kind.exe delete cluster` + explicit `docker network rm kind` (the same recurring leftover-network finding from R10/R12) + local image removal. Final verification: `docker ps -a`, `docker network ls`, `docker volume ls` all grep-empty for every R13 scenario name.

## R13 STATUS: **PASS**
All 8 experiments actually executed against live containers/clusters; every symptom was investigated using only real dashboards/APIs/logs before the root cause was revealed; every root cause was confirmed with captured evidence, not guessed; every fix was applied and recovery independently re-verified; 6 real environment/tooling bugs were hit, root-caused, and fixed along the way (none hidden); clean, verified teardown; $0 cost throughout.
