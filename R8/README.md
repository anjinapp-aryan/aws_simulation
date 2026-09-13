# R8 — Distributed Tracing

Runnable lab: `labs/r8-distributed-tracing/`. Docs: `GAP-ANALYSIS.md`, `REUSE-AUDIT.md`, `ARCHITECTURE.md`, `R8-REPORT.md` (full results, real bugs found/fixed, PASS status).

```bash
cd labs/r8-distributed-tracing
./scripts/run.sh                     # start stack, create Toxiproxy proxies
./scripts/status.sh
./scripts/baseline.sh 1              # R8-01
./scripts/slow-db.sh on|off          # R8-02
./scripts/break-db.sh cut|restore    # R8-03
./scripts/break-cache.sh cut|restore # R8-04
./scripts/async-trace.sh             # R8-05
./scripts/consumer-failure.sh stop|start   # R8-06
./scripts/error-trace.sh             # R8-07
./scripts/sampling.sh 1.0 20         # R8-09
./scripts/verify.sh
./scripts/cleanup.sh
```

Dashboards: Jaeger UI `:63686`, Traefik `:63081`, RabbitMQ Management UI `:63672` (guest/guest), Grafana `:63300`, Prometheus `:63090`, Dozzle `:63888`.
