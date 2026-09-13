# R6 — Caching Layer (ElastiCache-equivalent)

Runnable lab: `labs/r6-caching/`. Docs: `REUSE-AUDIT.md`, `ARCHITECTURE.md`, `R6-REPORT.md` (full results, real bugs found/fixed, PASS status).

```bash
cd labs/r6-caching
./scripts/run.sh                    # start stack, create Toxiproxy proxy
./scripts/status.sh
curl "http://localhost:61080/cached-item?id=1"   # R6-01/02
./scripts/cache-flush.sh
./scripts/break-cache.sh cut|latency              # R6-03/04
./scripts/stampede.sh 300 1s                      # R6-05
./scripts/kill-primary.sh                         # R6-06
./scripts/fix.sh              # cache cut/latency fix
./scripts/fix-failover.sh     # after kill-primary.sh
./scripts/verify.sh
./scripts/cleanup.sh
```

Dashboards: Traefik `:61081`, Grafana `:61300`, Prometheus `:61090`, redis-commander `:61082`, Dozzle `:61888`.
