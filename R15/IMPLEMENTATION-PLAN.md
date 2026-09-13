# R15 — Implementation Plan (Phase B, not started)

## Build order
1. Stand up the base system: Traefik + app (order-service/payment-service, extended with cache-aside read + pooled DB write) + Valkey + Patroni/etcd/HAProxy + Kafka/Debezium + Envoy (2 app replicas) + pgBackRest, reusing each component's exact R4/R6/R9/R11/R13/R14 configuration.
2. Stand up observability: Prometheus/Grafana (import/extend existing dashboards), Jaeger, Dozzle, Kafka UI, pgweb — all reused unmodified.
3. Verify baseline health of the WHOLE standing system before any fault is designed against it (equivalent to R15-01's own "level 0").
4. Implement R15-01 (single fault) first — lowest risk, validates the standing system can host a real investigation.
5. Implement R15-02 → R15-06 in order, each validated (baseline → inject → investigate → reveal → fix → verify → teardown-or-reset-to-baseline) before moving to the next, per this project's standing incremental-execution discipline.
6. For each scenario: `investigate.md` (symptom-only), `inject.sh` (hidden), `reveal.md` (spoiler, root cause / contributing factor / secondary symptom separated, architectural improvement + new-failure-mode consideration), `fix.sh`, `evidence/`.
7. Final `R15-REPORT.md` consolidating all 6 scenarios' real results, MTTD/MTTR/RTO/RPO table, real bugs found during implementation (expected, per this project's history), and cleanup proof.

## Reuse steps (no new infrastructure)
Copy/compose R4/R6/R9/R11/R13/R14's exact service definitions; no new Docker images beyond the already-proven ones; no new fault-injection library (per `CHAOS-TOOL-AUDIT.md`); no new dashboard (per `VISUALIZATION-AUDIT.md`).

## Cleanup
`docker compose down -v` after each scenario or at minimum at the end of the full sequence; explicit `docker ps -a`/`network ls`/`volume ls` grep-empty verification, matching every prior phase's $0 proof standard.

## Not started
No code, compose file, or manifest has been written for R15. This document and the other 8 Phase A files are the complete audit/design deliverable. Awaiting **"[R15] ARCHITECTURE APPROVED"**.
