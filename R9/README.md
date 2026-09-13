# R9 — Circuit Breaking & Service Resilience

Runnable lab: `labs/r9-circuit-breaker/`. Docs: `GAP-ANALYSIS.md`, `REUSE-AUDIT.md`, `ARCHITECTURE.md`, `R9-REPORT.md` (full results, real bugs found/fixed, PASS status).

```bash
cd labs/r9-circuit-breaker
./scripts/run.sh                  # start stack, create Toxiproxy proxy
./scripts/status.sh                # breaker + Envoy cluster state
curl "http://localhost:64000/order?id=1"      # breaker-protected
curl "http://localhost:64080/order-raw?id=1"  # via Envoy, unprotected
./scripts/break-db.sh cut|restore
./scripts/cleanup.sh
```

Dashboards: Envoy admin `:64901/clusters`, Grafana `:64300`, Prometheus `:64090`, Dozzle `:64888`.
