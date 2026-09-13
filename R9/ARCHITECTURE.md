# R9 — Proposed Architecture (pending approval, nothing built yet)

## Topology
```
Client (curl/vegeta)
  |
  v
Envoy (NEW - real proxy, real circuit-breaking/outlier-detection config,
       real admin UI at :9901/clusters showing live host health)
  |
  v
app (ADAPTED - R4's server.py pattern + PyBreaker wrapper around the
     DB call, one new /breaker-status endpoint)
  |
  v
PgBouncer -> Postgres (REUSED, R4 config)
  ^
Toxiproxy (REUSED, R4-R8 pattern - fault injection on DB)

Observability (all REUSED unchanged):
  Prometheus, Grafana, Dozzle
```

## Component classification
| Component | Status |
|---|---|
| Envoy (proxy + circuit breaker + admin UI) | **NEW** |
| PyBreaker wrapper in app | **ADAPTED** - existing app pattern + ~50 lines |
| Postgres, PgBouncer, Toxiproxy, Prometheus, Grafana, Dozzle | **REUSED unchanged**, config from R4 |

## Two distinct, real circuit-breaking patterns demonstrated side by side
1. **Infrastructure-level (Envoy)**: watches HTTP response codes from the app itself, ejects the app host from its load-balancing pool after consecutive 5xxs - the AWS App Mesh-style pattern (App Mesh's data plane literally is Envoy).
2. **Application-level (PyBreaker)**: wraps the DB call inside the app; after N consecutive failures, "opens" and fails fast without even attempting a DB connection - the resilience4j/Hystrix-successor pattern.

## Experiments (7)

| ID | Objective | Real mechanism | What I SEE | Fidelity |
|---|---|---|---|---|
| R9-01 Normal | Baseline requests, both breakers closed/healthy | Real Envoy proxy, real PyBreaker CLOSED state | Envoy admin `/clusters` (healthy host), app `/breaker-status` = closed | REAL |
| R9-02 Infra-level circuit opens | Cut DB via Toxiproxy -> app returns 5xx -> Envoy's outlier detection ejects the app host after consecutive failures | Real Envoy outlier ejection | Envoy admin stats show the host ejected; client gets Envoy's own 503 "no healthy upstream" instead of hitting the app at all | REAL |
| R9-03 App-level circuit opens (fail fast) | Same DB outage - PyBreaker opens after N consecutive DB failures | Real breaker state transition CLOSED->OPEN | `/breaker-status` shows `open`; **measured** latency drops from full connection-timeout to near-instant once open | REAL |
| R9-04 Half-open recovery | Wait for PyBreaker's reset timeout, restore DB, observe HALF_OPEN -> CLOSED transition | Real breaker state machine | `/breaker-status` polled over time shows the real transition sequence | REAL |
| R9-05 Thundering-herd protection (measured, not assumed) | Vegeta load during DB outage, compare WITH vs WITHOUT the app-level breaker | Real aggregate latency/throughput difference under sustained load | Vegeta report before/after - actual numbers, not predicted | REAL |
| R9-06 Envoy re-inclusion | Restore DB, observe Envoy automatically re-including the app host once it passes health checks again | Real Envoy passive health-check recovery | Envoy admin `/clusters` host state flips back to healthy | REAL |
| R9-07 Cascading-failure prevention | Reproduce R5-style pressure (many concurrent requests hitting a dead DB) with and without the app-level breaker; show whether the app stays responsive to `/health` either way | Real concurrent load via Vegeta, real thread/connection behavior | Compare `/health` responsiveness during the outage in both configurations | REAL |

## REAL vs BEHAVIOR-EQUIVALENT vs NOT POSSIBLE (architecture-level)
- **REAL**: Envoy's actual outlier-detection/circuit-breaking engine, PyBreaker's actual state machine, real Toxiproxy-injected DB failure, real measured latency/throughput differences.
- **BEHAVIOR-EQUIVALENT**: this Envoy config standing in for "AWS App Mesh circuit breaking" - same underlying Envoy engine, but no App Mesh control plane, no AWS-managed xDS.
- **NOT POSSIBLE LOCALLY**: App Mesh's own control plane and AWS console, real cross-AZ mesh behavior, CloudWatch/X-Ray integration with App Mesh telemetry.

## $0 proof
Envoy and PyBreaker both free/OSS. All other components already verified free in R4-R8. No AWS credential anywhere.

## What will NOT be built
No Hystrix (deprecated), no Istio/App Mesh control plane, no custom circuit-breaker dashboard.

---

Waiting for **"R9 ARCHITECTURE APPROVED"** before writing any docker-compose.yml, scripts, or app code.
