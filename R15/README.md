# R15 — Architect / Production Chaos Capstone

Runnable lab: `labs/r15-capstone/`. Docs: `ARCHITECTURE.md`, `INCIDENT-SCENARIOS.md`, `INCIDENT-RESULTS.md`, `FINAL-REPORT.md`, and one report per incident in `incidents/`.

R15 composes already-proven R1–R14 components into a single standing multi-subsystem system, then runs real production-style incidents against it. Nothing here is a new mechanism — it is the earlier phases' real machinery wired together so that a fault in one subsystem can be investigated the way a real on-call engineer would, with competing hypotheses to eliminate.

## Prerequisite chain

```
R14  (labs/r14-ha-dr)          3-node Patroni PostgreSQL cluster + etcd + HAProxy
  |                            provides the order-side database and the
  |  prerequisite              external Docker network "patroni-src_demo"
  v
R15  (labs/r15-capstone)       Kafka + Debezium CDC, order-service x2 behind
                               Envoy, payment-service, Valkey cache, Toxiproxy,
                               Jaeger, Prometheus/Grafana, pgweb, Dozzle
```

R15 does **not** duplicate the Patroni cluster — it joins R14's real one. `scripts/run.sh` brings up both, in order, and handles every prerequisite between them.

## START

```bash
cd labs/r15-capstone
./scripts/run.sh
```

That is the whole documented path. It is idempotent — safe to run again against an already-running environment — and it never deletes data.

It takes roughly 3–6 minutes from nothing on a first run (most of it the Patroni image build and the Envoy health-check settling described below).

### What run.sh actually does, and why

Each step exists because the environment genuinely does not work without it. They are worth understanding rather than treating as a black box:

| Step | Why it is required |
|---|---|
| Build the `patroni` image | The official `patroni/patroni` compose file references an image named `patroni` that it does not build itself. Without this, `docker compose up -d` fails with `pull access denied for patroni`. |
| Start the 3-node Patroni cluster | Provides the order-side database and creates the external network R15 attaches to. |
| Make `patroni1` the leader | `debezium/order-connector.json` is deliberately pinned to the hostname `patroni1` — that pinning is INCIDENT-02's documented root cause and is not "fixed" here. Debezium creates a logical replication slot, which only a primary accepts, so `patroni1` must hold the leader role at registration time. Leader election on a fresh cluster is genuinely non-deterministic, so the script performs a real `patronictl switchover` when some other node won. |
| Set `wal_level=logical` | Patroni's demo cluster defaults to `wal_level=replica`. Debezium's `pgoutput` plugin requires logical replication. Set through Patroni's own persistent DCS configuration (REST `PATCH /config`) and applied with a real rolling restart — never by editing the vendored official repo. |
| Create the Toxiproxy proxies | `order-service-1` reaches the database through `toxiproxy:56000` (`orderdb`), `order-service-2` through `toxiproxy:56010` (`orderdb2`), and the cache through `toxiproxy:56001` (`cache`). These are the exact proxies INCIDENT-01 and INCIDENT-03 attach their toxics to. Created before the applications start, so the apps never boot against a proxy that does not exist yet. |
| Register the Debezium connectors | `debezium/*.json` are configuration only; Kafka Connect does nothing until they are POSTed to its REST API. The script waits for the connector **and its task** to reach `RUNNING` — HTTP 200 on creation only means the config was accepted, and a task can fail immediately afterwards. |

## VERIFY

```bash
./scripts/verify.sh
```

A container being up is not evidence. This asserts real behaviour and exits non-zero if anything fails:

- 3 Patroni members healthy, 2 replicas streaming, leader is `patroni1`
- `wal_level=logical`, PostgreSQL reachable on the leader
- order-service healthy through Envoy, both replicas healthy in Envoy's own view
- both Debezium connectors `RUNNING` — connector **and** task
- a real Saga round trip: `/place-order` → `CREATED` → real outbox → Debezium → Kafka → payment-service → `CONFIRMED`
- cache-aside: first read `source: db`, second read `source: cache`

Expect `PASSED: 13   FAILED: 0`. Anything else means the environment is not reproduced — do not start an incident on it.

## SEE — what to open, and what healthy looks like

Visualization is the existing mature tooling. Nothing custom was built.

| Tool | URL | What healthy looks like | What changes during a failure |
|---|---|---|---|
| Kafka UI | http://localhost:59180 | Both connectors `RUNNING`, `outbox.event.*` topics with a growing offset | INCIDENT-05: connector silently `PAUSED`, offsets frozen |
| Jaeger | http://localhost:59686 | `checkout` / `order-status` traces, `cache-get` ~1–2ms, `order-status-db-read` a few ms | INCIDENT-01: `order-status-db-read` dominates the span breakdown |
| Envoy admin | http://localhost:59901/clusters | Two endpoints, both `health_flags::healthy` | INCIDENT-03: real per-host `ejections_enforced_total` as one replica is cycled out |
| Grafana | http://localhost:59300 | Anonymous access, Prometheus datasource provisioned | golden-signal comparison across an incident window |
| pgweb (order) | http://localhost:59081 | `orders` and `outbox` tables on the Patroni leader | orders stuck in `CREATED` when CDC is broken |
| pgweb (payment) | http://localhost:59082 | `paymentdb` rows advancing | payment side idle when the relay is broken |
| Dozzle | http://localhost:59888 | Live logs across every container | the real error text, in real time |
| Toxiproxy | http://localhost:59474/proxies | Three proxies, `toxics: []` | the injected toxic appears here — the ground truth of what was broken |

`./scripts/status.sh` prints the same picture in the terminal, read-only.

## BREAK → INVESTIGATE → RECOVER → VERIFY

The incidents themselves are in `R15/incidents/INCIDENT-01.md` … `INCIDENT-06.md`, each with its real evidence in `R15/evidence/incident-0N/`. Read the symptom section first and investigate before reading the root cause.

Worked example — INCIDENT-01, using its documented mechanism exactly:

```bash
# BASELINE - a few reads, expect ~10-17ms
curl -s -o /dev/null -w "%{time_total}s\n" "http://localhost:59080/order-status?id=demo-1"

# BREAK - real 400ms Toxiproxy latency toxic on order-service-1's DB path
curl -s -X POST http://localhost:59474/proxies/orderdb/toxics \
  -H "Content-Type: application/json" \
  -d '{"name":"latency_down","type":"latency","stream":"downstream","attributes":{"latency":400,"jitter":0}}'

# INVESTIGATE - read latency now, then eliminate competing hypotheses in
# Jaeger (span breakdown), Envoy admin (are both replicas healthy?) and
# Kafka UI (is CDC actually involved?) before looking at Toxiproxy.

# RECOVER
curl -s -X DELETE http://localhost:59474/proxies/orderdb/toxics/latency_down

# VERIFY - latency back to baseline, then full health
./scripts/verify.sh
```

## STATUS / CLEANUP

```bash
./scripts/status.sh            # read-only snapshot, changes nothing
./scripts/cleanup.sh           # tear down R15, leave the R14 foundation running
./scripts/cleanup.sh --all     # tear down R15 and the R14 Patroni foundation
```

`cleanup.sh` is the only script that destroys anything.

## Not automated (deliberate)

**INCIDENT-06 (pgBackRest)** needs pgBackRest installed on the Patroni leader with the `demo` stanza created, exactly as set up in R14 Experiment 5 (`R14/EXPERIMENT-RESULTS.md`). That is a package installation inside the leader container, not part of the standing system, and adding a multi-minute install to every startup for one bonus incident is the wrong trade. Follow R14's own documented procedure when you want to run INCIDENT-06; the other five incidents need nothing beyond `run.sh`.

## Troubleshooting

Real problems hit while building and testing this flow:

- **`pull access denied for patroni`** — the Patroni image was never built. `run.sh` handles it; if running the compose files by hand, `cd ../r14-ha-dr/patroni-src && docker build -t patroni .` first.
- **A replica shows `state: streaming`, not `running`** — that is the healthy state for a replica that has established replication. Only a leader reports `running`. Counting only `running` will never reach 3.
- **Envoy shows one endpoint `/failed_active_hc` right after startup** — order-service takes ~2s to initialise its schema, so Envoy's first health check can land while it is still starting. Envoy then falls back to its default `no_traffic_interval` (60s) before rechecking an idle cluster, so the replica can stay flagged for up to a minute despite already serving. `run.sh` waits this out while generating real traffic; it resolves on its own.
- **`docker-credential-desktop not found`** — remove the `credsStore` key from `~/.docker/config.json` (a known quirk of this environment, safe for these public images).

## AWS honesty

**REAL LOCAL BEHAVIOUR**: Patroni leader election and failover, PostgreSQL logical replication, Debezium CDC, Kafka delivery, Envoy health checking and outlier ejection, cache-aside semantics, Toxiproxy network faults.

**BEHAVIOUR-EQUIVALENT**: the *shape* of an RDS Multi-AZ failover, an MSK-backed event pipeline, and an ALB/target-group health-check rotation — same class of behaviour, different implementation and timing characteristics.

**NOT REPRODUCED**: AWS control-plane behaviour, real VPC networking, IAM, CloudWatch metrics and alarms, RDS's synchronous Multi-AZ replication guarantee (this cluster is async by default, and R14 measured real data loss because of it). Local Patroni is not RDS, local Kafka is not MSK, local Grafana is not CloudWatch.

Everything runs locally on Docker. AWS spend: **$0**.
