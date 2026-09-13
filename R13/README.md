# R13 — Production Troubleshooting / Incident Investigation

Runnable lab: `labs/r13-incident-investigation/<01-08>/`. Docs: `GAP-ANALYSIS.md`, `REUSE-AUDIT.md`, `ARCHITECTURE.md`, `R13-REPORT.md` (full results, real bugs found/fixed, PASS status).

Each scenario is a self-contained incident:
- `investigate.md` — the symptom-only brief and the 12-step investigation structure. Read this first, not `inject.sh`.
- `inject.sh` — the hidden fault (don't read before investigating).
- `reveal.md` — the root cause, spoiler-tagged, opened only after investigating.
- `fix.sh` — the mitigation + recovery verification.
- `evidence/` — real captured evidence (timestamps, command output, trace/flow data) from the actual run.

| # | Scenario | Reuses | Fault mechanism |
|---|---|---|---|
| 01 | High latency | R8 (DB+cache+Jaeger+Grafana) | Toxiproxy DB latency + small PgBouncer pool |
| 02 | HTTP 5xx spike | R9 (Envoy+PyBreaker, 2 replicas) | Toxiproxy timeout on one replica's DB path |
| 03 | Queue backlog | R7 (RabbitMQ) | Toxiproxy DB latency on consumer's DB write |
| 04 | Resource pressure | R10 (`kind`) | Real `stress-ng` exceeding a pod memory limit |
| 05 | Cascading failure | R11 (Debezium/Kafka Saga) | Toxiproxy latency on order-service's own DB |
| 06 | Network/security failure | R12 (`kind`+Cilium) | Mislabeled "rollout" replica missing a NetworkPolicy match |
| 07 | Cache failure | R6 (Valkey) | `maxmemory` below Valkey's own baseline footprint |
| 08 | Distributed transaction failure | R11 (Debezium/Kafka Saga) | Kafka Connect connector paused via REST |

Compose-based scenarios (01, 02, 03, 05, 07, 08): `cd labs/r13-incident-investigation/<NN>-name && docker compose up -d --build`, then create the scenario's Toxiproxy proxies / register Debezium connectors as shown in that scenario's `inject.sh`/timeline, then `./inject.sh`, investigate, `cat reveal.md`, `./fix.sh`, `docker compose down -v`.

`kind`-based scenarios (04, 06) need `kind`/`cilium` run via PowerShell (the same real Windows/Git-Bash PATH-translation quirk documented in R10/R12):
```powershell
$env:PATH = "D:\WORK_SPACE\aws_simulation\.tools;" + $env:PATH
cd labs\r13-incident-investigation\04-resource-pressure
kind.exe create cluster --config kind-config.yaml
kind.exe load docker-image r13-04-app:v1 --name r13-04
```
then `kubectl apply -f manifests/`, `./inject.sh`, investigate, `cat reveal.md`, `./fix.sh`, and `kind.exe delete cluster --name r13-04` (+ `docker network rm kind`) via PowerShell again to tear down.
