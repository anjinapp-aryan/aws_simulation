# R9 Gap Analysis

| Capability | Simulated? | Phase | Remaining gap |
|---|---|---|---|
| IAM/task credentials | Yes | R1 | — |
| ALB routing/health | Yes | R2/R3 | — |
| Container lifecycle | Yes | R3/R5 | — |
| DB connectivity/pooling/latency | Yes | R4 | — |
| CPU/mem pressure, cascading failure | Yes | R5 | — |
| Caching/failover | Yes | R6 | — |
| Async messaging/DLQ/ordering | Yes | R7 | — |
| Distributed tracing | Yes | R8 | — |
| **Circuit breaking / service resilience** | **No** | — | **Full gap** |
| Autoscaling | No | — | Mostly NOT POSSIBLE LOCALLY (AWS control-plane scaling policies aren't reproducible) - low hands-on value, deprioritized |
| API Gateway/rate limiting | No | — | Open gap, lower novelty (Traefik already has built-in rate-limit middleware, small addition) |
| Secrets management/rotation | No | — | Open gap |

## Why circuit breaking is the next best topic
1. **Direct extension of R5's cascading-failure work**: R5 showed a failing dependency propagating into a degraded/unhealthy service. Circuit breaking is the *mitigation* for exactly that failure mode - the natural next question after "I saw cascading failure" is "how do you stop it from cascading?"
2. **High interview value**: circuit breaker states (closed/open/half-open), the AWS App Mesh (Envoy-based) vs. application-library (resilience4j/PyBreaker-style) distinction, and "fail fast vs. fail open" trade-offs are standard Staff/Architect questions.
3. **New, genuinely strong AWS mapping**: `envoyproxy/envoy` is Apache-2.0, extremely active, and is literally the data plane AWS App Mesh runs on top of - this is not just "behavior-equivalent," using real Envoy circuit-breaking config is about as close to production AWS mesh behavior as a local lab can get.
4. **Composes two distinct real patterns**: infrastructure-level circuit breaking (Envoy, in front of the DB-calling app) and application-level circuit breaking (a real Python library), letting the lab honestly contrast both approaches - a common real architectural decision.
5. **Reuses R4's DB failure-injection mechanism (Toxiproxy) directly** - no new fault-injection tooling needed, just a new consumer of it.
