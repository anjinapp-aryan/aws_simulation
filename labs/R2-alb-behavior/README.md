# Lab R2 — ALB-Behavior Simulation (real, $0)

Real reverse-proxy routing + real health checks + real failover, entirely local.

## Reused (unmodified)
`traefik:v3.1` — MIT, 64.8k stars, chosen over nginx specifically because its real-time dashboard is free and built-in (nginx's equivalent is a paid feature).

## Built (glue only)
`app/server.py` (~30 lines) — the one gap found: no existing tiny demo server (including `traefik/whoami`) supports failing `/health` independently of the app itself, which Experiment 5 needs. `docker-compose.yml`, `traefik-dynamic.yml`, 8 small scripts.

## What is real vs. not
**Real**: every container start/stop, every HTTP request, every health-check probe, every routing decision.
**Not AWS-identical**: Traefik's health-check/routing algorithm is Traefik's own, not AWS ALB's exact implementation. AWS-specific behavior (deregistration delay, connection draining, cross-zone balancing) is NOT reproduced — see `R2-REPORT.md` §15.

## Run it
```bash
bash scripts/run.sh
bash scripts/test.sh 10
```
Dashboard: http://localhost:18081/dashboard/

## Break it (real container failure)
```bash
bash scripts/inject-failure.sh
bash scripts/diagnose.sh
```

## Fix it
```bash
bash scripts/fix.sh
```

## Break it differently (container stays up, only health fails — proves RUNNING != HEALTHY)
```bash
bash scripts/break-health.sh
bash scripts/fix-health.sh
```

## Tear down
```bash
bash scripts/cleanup.sh
```

Full report, evidence, and the Windows/Docker-Desktop workaround explanation: `R2-REPORT.md`.
