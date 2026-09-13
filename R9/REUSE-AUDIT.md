# R9 Reuse Audit — Circuit Breaking / Service Resilience

## Searches run (real, GitHub Search API)
| Query | Result |
|---|---|
| `circuit breaker local simulation docker` | 0 results |
| `envoy circuit breaker demo docker compose` | 0 results |

No integrated tool exists - consistent with every prior audit.

## Candidates

| Component | Repository | Capability | License | Activity | Decision | Reason |
|---|---|---|---|---|---|---|
| Infra-level circuit breaking | `envoyproxy/envoy` | Real proxy with real circuit-breaking primitives (max connections/pending requests, consecutive-5xx outlier ejection), real admin interface (`/stats`, `/clusters`) showing live circuit state | Apache-2.0 (verified) | 28,906★, commits daily - extremely active | **REUSE** | Mature, official, and - uniquely valuable here - **App Mesh's actual data plane is Envoy**, so this is closer to real AWS behavior than most "behavior-equivalent" substitutions in this project |
| App-level circuit breaking | `danielfm/pybreaker` | Real Python circuit-breaker library (closed/open/half-open state machine, configurable failure threshold and reset timeout) | BSD-3-Clause (verified) | 693★, active (pushed ~2 months ago) | **REUSE** | Real, small, widely used pattern-equivalent to resilience4j/Hystrix for Python, directly usable as a thin wrapper around the existing DB call |
| Legacy alternative (rejected) | `Netflix/Hystrix` | Circuit breaker library that popularized the pattern | License shows `None` on GitHub (unclear) | 24,478★ but **officially in maintenance mode since 2018**, no meaningful new development | **REJECT** | Explicitly deprecated by Netflix; would teach an outdated pattern instead of the current one (Envoy/App Mesh, resilience4j-style libraries) |
| DB fault injection | Toxiproxy (already in the stack) | Real TCP fault injection | MIT (verified in R4) | proven across R4-R8 | **REUSE, carried forward unchanged** | No new fault-injection tool needed - circuit breaking is the new *reaction* to an already-proven *cause* |
| Visualization | Envoy's own admin interface | Real, live circuit-breaker/cluster-health stats page | Apache-2.0 | bundled with Envoy | **REUSE** | No custom dashboard needed; Grafana/Dozzle (already in stack) reused unchanged for the app-level breaker's state logging |

## Estimated custom code
~40-60 lines: PyBreaker wrapper around the existing DB call (from R4's `server.py` pattern) + an endpoint exposing the breaker's current state (`closed`/`open`/`half-open`) for evidence capture. Envoy itself needs only a YAML config file (`envoy.yaml`), not code.

## Docker services (estimate)
`envoy` (NEW), `app` (ADAPTED - PyBreaker wrapper), `postgres`+`pgbouncer` (REUSED, R4 config), `toxiproxy` (REUSED), `dozzle`, `grafana`, `prometheus` (REUSED for the app-level breaker's exposed metric). ~8 services.

## $0 proof
Envoy and PyBreaker both free/OSS. All other components already verified free in R4-R8. No AWS credential anywhere.

## What will NOT be built
No custom circuit-breaker dashboard (Envoy admin UI covers infra-level; a simple `/breaker-status` JSON endpoint plus existing Grafana covers app-level - no new visualization tool). No Hystrix (deprecated). No service mesh control plane (Istio/App Mesh itself) - just the Envoy data-plane pattern, which is the part that's actually reproducible and educational locally.
