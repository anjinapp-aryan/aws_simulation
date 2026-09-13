# R8 Gap Analysis

| Capability | Simulated? | Phase | Remaining gap |
|---|---|---|---|
| IAM/task credentials | Yes | R1 | — |
| Load balancing/health | Yes | R2/R3 | — |
| Container lifecycle | Yes | R3/R5 | — |
| DB connectivity/pooling | Yes | R4 | — |
| CPU/mem pressure, single-service cascading failure | Yes | R5 | — |
| Caching/failover | Yes | R6 | — |
| Async messaging/DLQ/ordering | Yes | R7 | — |
| **Distributed tracing / cross-service request correlation** | **No** | — | **Full gap - deferred explicitly in R5 and R6 audits as "stretch, not core" both times** |
| Circuit breakers | No | — | Open gap |
| API Gateway/rate limiting | No | — | Open gap (partially coverable via Traefik middleware, lower value) |

## Why tracing is the next best topic
1. **Explicitly deferred twice already** (R5 §Jaeger cost/benefit, R6 REFERENCE-only decision) - this is unfinished business, not a new idea.
2. **Highest remaining interview value**: "how do you debug a slow request across microservices in production" is a defining Staff/Architect-level question, and R1-R7 built exactly the multi-service stack (Traefik → app → cache → DB → queue) needed to demonstrate it properly - a trace can now span real components we already have running, which wasn't true before R7 existed.
3. **Genuinely new failure modes**: a slow span buried in one hop of a request chain, a trace that silently loses context across a queue boundary (async trace propagation is a real, hard problem), sampling trade-offs - none of these exist in R1-R7's per-service, metrics-only view.
4. **Strong reuse available** (see audit): Jaeger is mature, Apache-2.0, has its own excellent real UI.
5. **$0, fully local.**

## What R8 will NOT do
Rebuild R1-R7's infrastructure. R8 adds tracing instrumentation to the existing R6/R7-style app pattern and stands up Jaeger alongside a **minimal** slice of already-proven components (Traefik, one cache call, one DB call, one queue publish) - not a full re-deployment of every prior lab.
