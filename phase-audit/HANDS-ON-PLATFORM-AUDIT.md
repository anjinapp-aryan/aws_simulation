# Hands-On Platform Audit — Visualization + Expanded Simulation Reuse

Scope: this turn's specific mandate — audit only, no implementation. Builds on `CURRENT-STATE.md`/`GITHUB-REUSE-AUDIT.md` (unchanged, still current) and adds the R1 lab's evidence plus a mandatory visualization search across 15 categories.

## 1. What we already have (updated with R1)

| Asset | Real execution? | Visualization? | Failure injection? | $0? |
|---|---|---|---|---|
| connectivity-test/serverless-api/event-pipeline + Ministack | Yes (S3/DynamoDB/SNS/SQS/Kinesis, real DLQ redrive) | No | Yes (poison message) | Yes |
| phase1/phase2/phase3 (33 md files) | Mostly no (Terraform static analysis only) | No | No (predicted, not run) | Yes |
| **Lab R1** (this session) | **Yes — real credential vending + real MinIO policy ALLOW/DENY** | **Yes — terminal ANSI flow diagram, built after confirming no fit existed** | **Yes — real policy break/fix, observed real AccessDenied flip to ALLOW** | **Yes** |

R1 is the first phase-adjacent artifact scoring near the 81/100 bar the pre-phase app layer set. It also already searched for visualization (found nothing narrow enough, built ~90 lines of ANSI) — this turn's mandate to search visualization broadly is a superset of that search, now done properly across 15 categories rather than one narrow query.

## 2. GitHub reuse audit — visualization (searched this turn, real results)

**Direct hit search** (4 compound queries: "aws local simulation dashboard topology", "ecs fargate local simulation visualization", "cloud architecture topology visualization realtime", "alb load balancer health check simulation docker") — **zero results on all four.** Confirms: no integrated "AWS-simulation-with-built-in-visualization" project exists. This is real negative evidence, not an assumption.

**Individual-purpose tools, verified via GitHub API:**

| Tool | Stars | License | Last push | Verdict |
|---|---|---|---|---|
| weaveworks/scope (network/container topology viz) | 5,909 | Apache-2.0 | 2023-07 — 3+ years stale | DO NOT USE — unmaintained |
| jaegertracing/jaeger (distributed tracing, request-flow waterfall UI) | 23,201 | Apache-2.0 | 2026-09-10 — very active | REUSE for request-flow visualization |
| openzipkin/zipkin (alternative tracing) | 17,456 | Apache-2.0 | 2026-08-06 | REFERENCE — Jaeger is the stronger fit, redundant to run both |
| prometheus/prometheus (metrics) | 66,045 | Apache-2.0 | 2026-09-11 | REUSE for real metrics (CloudWatch-Metrics-equivalent) |
| grafana/grafana (dashboards) | 76,692 | AGPL-3.0 | 2026-09-11 | REUSE for real dashboards (CloudWatch-Dashboard-equivalent) |
| portainer/portainer (container visualization) | 38,482 | Zlib | 2026-09-10 | REUSE for container/ECS-task-equivalent visualization |
| bcicen/ctop (terminal container metrics) | 17,837 | MIT | 2024-07 — 14mo stale | REFERENCE only, Portainer supersedes it |
| im2nguyen/rover (interactive Terraform state/graph explorer) | 3,325 | MIT | 2025-07 — 14mo stale, but functionally narrow/stable | ADAPT for Terraform visualization (VPC/module graphs) |
| cycloidio/inframap (tfstate/HCL to graph) | 2,064 | MIT | 2026-04 — active | REFERENCE — Rover is more interactive, prefer it as primary |
| LocalStack's own dashboard | — | Paid (LocalStack Desktop) | — | DO NOT USE — violates $0 |
| returnvalue/flocidashboard (Django UI for "Floci" local AWS emulator) | 20 | unknown | 2026-09-01 | REFERENCE ONLY — too new/unproven (20 stars) to depend on; the underlying "Floci" emulator itself is unverified against the same API-shape-vs-real-behavior test that disqualified Ministack for ECS/ALB/RDS |

## 3. GitHub reuse audit — expanded simulation categories (beyond R1's IAM scope)

| Category | Existing solution | Decision | Why |
|---|---|---|---|
| VPC/network topology + break/restore | No integrated tool found; Docker's own bridge networks + iptables/tc netem (mature, built into every Linux kernel, not a GitHub repo but a real OS mechanism) | BUILD thin glue only | Real network partition/latency injection via tc netem/iptables inside containers is genuinely real behavior, zero new dependency, already how the industry does local chaos testing |
| SG-equivalent block/restore | Same as above — Docker network disconnect/reconnect, or iptables rule toggling, is REAL packet-level blocking, not a mock | BUILD thin glue | No mature "simulate an AWS Security Group locally" project exists; the underlying primitive (real firewall rule) is simpler and more real than any wrapper would be |
| ALB / health-check / 503 | nginx / Traefik (both mature, MIT/BSD, already selected in prior roadmap as R2) | REUSE, unchanged decision | Traefik in particular has a real-time dashboard built in — closes part of the visualization gap for free |
| ECS-equivalent (run/stop/restart containers, health checks) | Docker Compose itself + Portainer for visualization | REUSE | Docker Compose already is real container orchestration at small scale; Portainer visualizes it |
| RDS failure simulation | Real Postgres/MySQL containers (official images) — stop container, wrong credentials, connection refusal are all REAL database behavior | REUSE (official DB images, not a wrapper project) | No wrapper needed; a real Postgres container IS the real behavior |
| Redis failure simulation | Real redis:7-alpine container (already running in the user's unrelated careerpilot_ai project, confirming it's a known-good pattern) | REUSE | Same reasoning — real Redis, real cache miss/timeout behavior |
| CloudWatch/observability | Prometheus + Grafana (above) | REUSE | Real metrics/dashboards; explicitly classify as BEHAVIOR-EQUIVALENT, not REAL AWS, per the mandated classification scheme |
| IAM/task-role | amazon-ecs-local-container-endpoints + MinIO | REUSE, already proven in R1 | Working, verified, evidence-backed |
| Request-flow animation | Jaeger (above) | REUSE | Real distributed traces through Client-proxy-app-DB, waterfall UI included, zero custom animation code needed |
| Terraform visualization | Rover (above) | ADAPT | Point it at candidates/AWS-ECS-Blueprint's state/plan for an interactive module graph — directly upgrades Phase 1/2's static dependency-graph Markdown into something you click through |

## 4. Can we achieve the desired experience at $0?

Yes, for everything except real VPC/SG/ALB/ECS/RDS AWS-specific enforcement semantics (unchanged from every prior audit — Ministack proven to fake these at the API-shape level). Everything else — real containers, real databases, real cache, real proxying, real tracing, real metrics, real network-level blocking via iptables/tc — is $0 and behavior-equivalent-or-better than an AWS-shaped mock, because it's real software doing real things, just not AWS's specific implementation.

## 5. Classification scheme (as mandated) applied to every reused tool

| Tool | Classification |
|---|---|
| MinIO (R1) | AWS-COMPATIBLE LOCAL SIMULATION (real S3 API surface + real policy enforcement, not AWS itself) |
| amazon-ecs-local-container-endpoints | REAL (it's the literal AWS-official protocol implementation, run locally) |
| nginx/Traefik as ALB | BEHAVIOR-EQUIVALENT (real health-check/failover behavior, not AWS ALB's exact API/semantics) |
| Real Postgres/Redis containers | BEHAVIOR-EQUIVALENT for RDS/ElastiCache (real database/cache behavior, not the AWS-managed wrapper) |
| Jaeger/Prometheus/Grafana | BEHAVIOR-EQUIVALENT for CloudWatch (real observability behavior, different product) |
| iptables/tc netem for SG/network failure | BEHAVIOR-EQUIVALENT (real packet blocking/latency, not AWS's specific SG/NACL implementation) |
| Ministack (S3/DynamoDB/SQS/SNS/Kinesis only) | AWS-COMPATIBLE LOCAL SIMULATION (proven real for these 5 services specifically) |
| Ministack (ECS/ALB/RDS) | API MOCK (proven fake — do not reuse for these) |

## 6. What should NOT be built
A custom visualization engine (four searches confirm nothing off-the-shelf integrates AWS-sim+viz, but the components — Jaeger, Prometheus/Grafana, Portainer, Rover — all exist and compose). A custom network-topology tool (Docker networks + iptables + Portainer's view already cover it). A custom Terraform visualizer (Rover exists). A custom tracing UI (Jaeger exists). Any wrapper around LocalStack Pro or paid features.

## 7. What genuinely needs building
Only glue: docker-compose wiring connecting Jaeger/Prometheus/Grafana/Portainer to the application stack; small scripts for iptables/tc netem-based network failure injection (following R1's inject/fix/verify pattern); Rover invocation against Blueprint's Terraform. Consistent with R1's actual build footprint (~250 lines of glue, zero framework).

## 8. Recommended architecture for the hands-on platform

```
Client (curl / browser)
   |
Traefik or nginx  --------------------> dashboard (built-in, real-time)
   | (health-checked)
App containers (existing serverless-api / event-pipeline, reused)
   |                    |                    |
Postgres/Redis      Jaeger (traces)      Prometheus (metrics)
(real DB/cache)          |                    |
                     Jaeger UI            Grafana (dashboards)

Portainer -- observes all of the above (containers, health, logs)
Rover -- separately visualizes the Terraform/Blueprint module graph
```
Every arrow above is either a real request/real data flow or a real metrics/trace pipeline — no component is an API-shape mock.

## 9. Phase scoring impact
R1 re-scores meaningfully higher than the earlier 45/100 Phase 3 average: Execution 16/20, Observation 16/20, Failure injection 17/20 (real policy break, real detected AccessDenied), Troubleshooting 12/20, Recovery/verification 16/20 -> ~77/100 — Good, close to the pre-phase app layer's 81/100. This is real evidence the CONCEPT-REUSE-RUN-BREAK-FIX-VERIFY pattern works when actually followed, closing the gap the phase-audit identified.

## 10. Answers to the 10 mandated questions

1. What do we already have? Real app-layer sim (81/100), 33 largely-unexecuted Markdown files (Phase 1-3), and R1 — the first phase-adjacent lab that actually hits the target pattern (~77/100).
2. What can be reused? MinIO + ecs-local-container-endpoints (proven, R1). Newly identified: Jaeger, Prometheus, Grafana, Portainer, Rover, nginx/Traefik, official Postgres/Redis images.
3. GitHub projects for missing simulation capability? Listed in full in section 3 above — RDS/Redis/ALB/observability/Terraform-viz all have mature, active, correctly-licensed candidates.
4. GitHub projects for visualization? Jaeger (request-flow), Prometheus+Grafana (metrics/dashboards), Portainer (containers), Rover (Terraform graph) — no single integrated tool exists (confirmed by 4 empty searches), so these four compose to cover the requirement.
5. Can we achieve $0? Yes, for everything except AWS-specific VPC/SG/ALB/ECS/RDS enforcement semantics, which remain correctly deferred to a real-AWS CHEAP_MODE lab.
6. Reuse vs adapt vs build? Reuse: 8 of 10 categories in section 3, unmodified. Adapt: Rover (point at Blueprint state), workshop labs (deferred, naming). Build: thin glue only (~200-300 lines per lab, R1's proven footprint).
7. New phase roadmap? See RECOMMENDED-ROADMAP.md (unchanged core sequence: R1 done -> R2 ALB/Traefik -> R3 minimal real-AWS VPC+SG) — now explicitly wire Jaeger/Prometheus/Grafana/Portainer into R2 onward as the standing observability+visualization layer, not a separate phase.
8. Smallest next hands-on lab? R2 — Traefik/nginx in front of 2 containers, Traefik's own dashboard for the visualization requirement (built-in, zero extra glue), kill/restore a backend, observe real 502-to-200 recovery.
9. What should NOT be built? Custom visualization engine, custom network simulator, custom Terraform grapher, custom tracing UI — all four searched-for and found to already exist maturely.
10. Recommended architecture? Section 8 above — a real small production-shaped stack (proxy -> app -> DB/cache, with tracing/metrics/dashboards attached), same shape the original prompt's mental model asked for, built entirely from reused components.
