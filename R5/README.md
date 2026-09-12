# R5 — Observability + Performance Pressure + Production Troubleshooting

Runnable lab: `labs/r5-observability/`. Docs: `REUSE-AUDIT.md`, `ARCHITECTURE.md`, `R5-REPORT.md` (full results, real bugs found/fixed, PASS status).

```bash
cd labs/r5-observability
./scripts/run.sh              # start stack, create Toxiproxy proxy
./scripts/status.sh
./scripts/load-vegeta.sh 10 15s /health   # R5-01
./scripts/cpu-stress.sh 30 2              # R5-02
./scripts/mem-stress.sh 300M              # R5-03
./scripts/break-backend.sh                # R5-04
./scripts/break-db.sh latency|severe|cut  # R5-05
./scripts/cascading-failure.sh            # R5-06
./scripts/fix.sh
./scripts/verify.sh
./scripts/cleanup.sh
```

Dashboards: Traefik `:58081`, Grafana `:53000`, Prometheus `:59090`, cAdvisor `:58082`, Dozzle `:58888`.
