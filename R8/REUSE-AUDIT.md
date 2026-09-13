# R8 Reuse Audit — Distributed Tracing

## Searches run (real, GitHub Search API)
| Query | Result |
|---|---|
| `distributed tracing local simulation docker microservices` | 0 results |
| `opentelemetry docker compose multi-service trace demo` | 0 results |

Consistent with every prior audit: no integrated "AWS X-Ray local simulator" exists.

## Candidates

| Repo | Stars | License | Last push | Capability | Decision |
|---|---|---|---|---|---|
| `jaegertracing/jaeger` | 23,203 | Apache-2.0 | 2026-09-10, active | Real distributed tracing backend + storage + **real, mature UI** (trace waterfall, service dependency graph) | **REUSE** - `jaegertracing/all-in-one` image, single container, zero extra infra (in-memory storage, sufficient for a lab) |
| `open-telemetry/opentelemetry-python` | 2,629 | Apache-2.0 | active | Official Python instrumentation SDK (spans, context propagation, OTLP exporter) | **REUSE** - the real instrumentation library, not a custom tracer |
| `open-telemetry/opentelemetry-collector` | 7,531 | Apache-2.0 | active | Vendor-neutral telemetry pipeline/collector | **REFERENCE** - adds a hop of complexity (app -> collector -> Jaeger) not needed for this lab's scope; app will export OTLP directly to Jaeger's built-in OTLP receiver instead |
| `grafana/tempo` | 5,471 | **AGPL-3.0** | active | Trace backend, Grafana-native | **REJECT for this phase** - AGPL caution (same category as prior license-diligence calls for Redis/Redpanda in R6/R7), and would need Grafana Tempo datasource wiring for a UI Jaeger already provides natively |
| `openzipkin/zipkin` | 17,456 | Apache-2.0 | active (last push ~5 weeks old vs Jaeger's daily activity) | Alternative real tracing backend | **REJECT** - Jaeger is more actively maintained and is the de-facto standard paired with OpenTelemetry today |
| `open-telemetry/opentelemetry-demo` | 3,339 | Apache-2.0 | active | Official ~20-microservice polyglot reference demo with full observability stack | **REFERENCE ONLY** - real and well-built, but adopting it would replace/duplicate R1-R7's own stack rather than extend it; used only for instrumentation-pattern reference, not deployed |

## Visualization decision
Jaeger's own UI (trace waterfall view, service dependency graph, span tag/log inspection) is the primary and sufficient visualization - real, bundled, no custom UI needed. Existing Grafana/Prometheus/Dozzle/Traefik dashboard/RabbitMQ Management UI are reused unchanged for the metric/log/queue side of each experiment, giving a genuine "correlate trace + metric + log" experience across tools that already exist.

## Custom code estimate
Extending the existing minimal-app pattern (R4/R6/R7's `server.py`) with OpenTelemetry auto/manual instrumentation: tracer setup (~15 lines), spans around the DB call, cache call, and queue publish (~10 lines each), OTLP exporter config (~10 lines). Estimated **~70-90 lines total** - the largest single instrumentation addition so far, but still thin glue around real SDK calls, not a custom tracer.

## Docker services (estimate)
`jaeger` (all-in-one), `app` (adapted), `postgres`+`pgbouncer` (reused config from R4), `valkey` (reused config from R6, single node - no Sentinel needed for this lab's scope), `rabbitmq` (reused config from R7), `toxiproxy` (fault injection, reused), `traefik`, `prometheus`, `grafana`, `dozzle`. ~11 services, all but `app` unmodified images.

## $0 proof
All images free/OSS. No AWS credential anywhere.

## What will NOT be built
No OpenTelemetry Collector hop (direct OTLP-to-Jaeger instead), no Tempo, no custom trace UI, no re-deployment of R6's Sentinel/replica topology or R7's full DLQ/retry queue chain (one queue is enough to demonstrate async trace-context propagation - the R7 failure modes themselves aren't being re-tested here).
