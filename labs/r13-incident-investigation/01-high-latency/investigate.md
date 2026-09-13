# R13-01 — INCIDENT: Checkout latency degraded

**Time:** incident starts when `inject.sh` is run (see evidence/ for exact timestamp).
**Business impact:** `/checkout` p95/p99 response time has increased significantly. Customers may be experiencing slow checkout.
**Scope:** single service (`app`), single endpoint (`/checkout`).

## Available tools
- Grafana: http://localhost:57300 (anonymous admin)
- Jaeger UI: http://localhost:57686
- Prometheus: http://localhost:57090
- Dozzle (logs): http://localhost:57888
- App direct: http://localhost:57080/checkout?id=1 (via Traefik)

## Your task
Do NOT read `inject.sh` or `reveal.md` yet. Investigate using only the tools above and the 12-step structure below. Record your findings in this file (append at the bottom) with real evidence (trace IDs, span durations, metric values, timestamps).

## 12-step investigation structure
1. **Symptom** — what is observed?
2. **Scope** — one endpoint? one service? all traffic?
3. **Metrics** — what does Grafana/Prometheus show?
4. **Logs** — what does Dozzle show for `app`, `pgbouncer`, `postgres`?
5. **Traces** — pull a slow trace from Jaeger. Which span dominates?
6. **Dependencies** — what does the slow span call downstream?
7. **Cross-signal correlation** — does the metric spike line up with the trace evidence and logs?
8. **Hypotheses** — list 2-3 plausible causes.
9. **Elimination** — for each hypothesis, what evidence confirms/rules it out?
10. **Root cause** — state it precisely, backed by evidence.
11. **Immediate mitigation** — what stops the bleeding right now?
12. **Permanent fix / prevention** — what changes so this doesn't recur silently?

## Hints available on request
- `curl http://localhost:57090/api/v1/query?query=pg_stat_activity_count` (if instrumented) or check `postgres_exporter` metrics.
- Toxiproxy control API is real and running at `http://localhost:57474/proxies` — real production engineers wouldn't have this, but you can inspect it as a stand-in for "what does the network/proxy layer show" (AWS equivalent: VPC flow logs / RDS Performance Insights).
