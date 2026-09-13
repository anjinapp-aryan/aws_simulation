# R8 — Proposed Architecture (pending approval, nothing built yet)

## Topology
```
Client (curl/vegeta)
  |
  v
Traefik (REUSED, R2/R3/R5/R6/R7 file-provider pattern)
  |
  v
app (ADAPTED - R6/R7's server.py pattern + OpenTelemetry instrumentation,
     one endpoint: /checkout)
  |         |            |
  v         v            v
Valkey    PgBouncer    RabbitMQ
(REUSED,  -> Postgres  (REUSED,
 single    (REUSED,     R7 config,
 node,     R4 config)   one queue)
 R6 config)
  ^
Toxiproxy (REUSED, R4-R7 pattern - fault injection on DB/cache)

consumer (ADAPTED - R7's consumer.py + OTel instrumentation, continues
          the same trace across the queue boundary)

All spans -> Jaeger (NEW, all-in-one, OTLP receiver + real trace UI)

Observability (all REUSED unchanged):
  Prometheus, Grafana (DB/cache metrics, carried from R4/R6)
  Dozzle (logs)
  RabbitMQ Management UI (queue state)
  Traefik dashboard (routing/health)
```

## Component classification
| Component | Status |
|---|---|
| Jaeger (all-in-one) | **NEW** - the one genuinely new piece |
| app instrumentation (OTel SDK, spans) | **ADAPTED** - existing app pattern + ~80 lines of tracing code |
| consumer instrumentation | **ADAPTED** - existing R7 consumer + trace-context propagation |
| Traefik, Valkey, Postgres, PgBouncer, RabbitMQ, Toxiproxy, Prometheus, Grafana, Dozzle | **REUSED unchanged**, config copied from R4/R6/R7 |

## Experiments (7)

| ID | Objective | Real mechanism | What I SEE | Fidelity |
|---|---|---|---|---|
| R8-01 Normal trace | One request touches cache+DB+queue, view full waterfall | Real OTel spans -> real Jaeger OTLP ingestion | Jaeger UI trace waterfall, all 4 spans (Traefik/app/DB/cache/publish) | REAL |
| R8-02 Slow dependency | Toxiproxy DB latency, identify which span is slow (not just "the request is slow") | Real injected latency, real span duration | Jaeger UI: the DB span visibly dominates the waterfall | REAL |
| R8-03 Dependency failure surfaced in trace | Cache cut (R6 pattern), app fails open to DB | Real exception, real span error tag | Jaeger UI: cache span marked as error, request still succeeds end-to-end | REAL |
| R8-04 Async context propagation | Does the trace survive the RabbitMQ hop? Determined experimentally, not assumed | Real OTel context injection into message headers + extraction in consumer | Jaeger UI: one trace ID spanning producer AND consumer, or a broken/split trace if propagation fails | REAL (the propagation mechanism itself is a standard OTel pattern) |
| R8-05 Sampling trade-off | Lower sampling rate, fire Vegeta load, count traces actually captured vs requests sent | Real Jaeger sampling config | Jaeger UI trace count vs Vegeta's real request count | REAL |
| R8-06 Service dependency graph | View Jaeger's System Architecture tab after several experiments | Real graph built from real span data | Jaeger UI dependency graph | REAL |
| R8-07 Correlate trace + metric + log | Take a slow trace's ID, cross-reference Dozzle log line and Grafana DB-latency panel timestamp | Real timestamp/ID correlation across 3 real tools | Jaeger + Dozzle + Grafana side by side | REAL |

## REAL vs BEHAVIOR-EQUIVALENT vs NOT POSSIBLE (architecture-level)
- **REAL**: OpenTelemetry SDK spans, real Jaeger ingestion/storage/UI, real Toxiproxy-injected latency/failure, real trace-context propagation (or lack thereof) across the queue.
- **BEHAVIOR-EQUIVALENT**: this stack standing in for "AWS X-Ray tracing a Lambda/ECS/SQS request chain" - same distributed-tracing concept, different backend/protocol.
- **NOT POSSIBLE LOCALLY**: AWS X-Ray's own service map/console, X-Ray's automatic SDK integration with managed AWS services (API Gateway, Lambda cold-start segments), CloudWatch ServiceLens.

## $0 proof
Jaeger all-in-one is free/self-hosted Apache-2.0. All other components already verified free in R4/R6/R7. No AWS credential anywhere.

## What will NOT be built
No OpenTelemetry Collector, no Tempo, no custom trace UI, no full re-deployment of R6's Sentinel topology or R7's DLQ/retry chain.

---

Waiting for **"R8 ARCHITECTURE APPROVED"** before writing any docker-compose.yml, scripts, or app code.
