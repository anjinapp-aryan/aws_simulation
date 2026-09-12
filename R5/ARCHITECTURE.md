# R5 — Final Architecture (as built and run)

```
Client
  |
  v
Traefik (v3.1, file-provider mode - R2/R3's proven Windows workaround)
  |
  v
app (R4's /db handler + R2's unhealthy-toggle, one file, unmodified image)
  |
  v
PgBouncer -> Postgres
  ^
Toxiproxy (DB fault injection - R4's mechanism, unchanged)

Observability:
  cadvisor -> Prometheus -> Grafana   (per-container metrics: BROKEN on this
                                        Docker Desktop, see REUSE-AUDIT.md/
                                        R5-REPORT.md §10 - root-caused, not
                                        hidden; docker stats/inspect used
                                        instead for CPU/mem evidence)
  postgres_exporter -> Prometheus -> Grafana (real, works)
  app logs -> Dozzle / docker logs (real, fixed - see report bug #4)

Load/failure (utility containers, not in the base stack):
  peterevans/vegeta  -> HTTP load
  colinianking/stress-ng -> CPU/mem pressure, staged into the RUNNING app
                             container via docker cp + docker exec (never
                             baked into the app image)
```

## Why this shape
- App container stays byte-identical to R4's image philosophy: no stress-ng install, no tracing SDK. Pressure and load are applied from outside.
- Toxiproxy, PgBouncer, Postgres, Traefik, Dozzle, Prometheus, Grafana are R2-R4 components, copied config-only, zero new custom code.
- `mem_limit: 128m` + `memswap_limit: 128m` on `app` (swap disabled) is new versus R3 — required for OOM to actually fire (see report bug #3).
- cAdvisor is deployed and real, but its per-container Docker enumeration does not work against this Docker Desktop daemon (API 1.54) — confirmed on two cAdvisor versions and with an explicit API-version pin. `docker stats`/`docker inspect` (already proven in R1-R4) are the real per-container CPU/memory evidence source for R5-02/03 instead.

## What was NOT built
Jaeger/OpenTelemetry tracing, pumba, any custom dashboard/UI, any change to the app Dockerfile.
