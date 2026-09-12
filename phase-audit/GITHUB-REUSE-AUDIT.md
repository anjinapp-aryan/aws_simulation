# GitHub Reuse Audit — Closing the Hands-On Gap

Searched specifically for tools that reproduce **real behavior**, not API-shape responses — the distinction proven necessary by the earlier finding that Ministack fakes ECS/ALB/RDS (real API responses, zero real containers/databases/load-balancers).

## Candidate 1 — `awslabs/amazon-ecs-local-container-endpoints`
| | |
|---|---|
| Purpose | Docker container providing a **local** ECS Task Metadata Endpoint + ECS Task IAM Role credential-vending endpoint |
| License | Apache-2.0 ✅ |
| Stars | 517 |
| Maintenance | Last push 2025-03-31 — ~18 months stale, but AWS-official and narrow-scope; check compatibility before use |
| Runnable | **Yes** — `docker-compose` based, genuinely runs |
| AWS required | **No** |
| Cost | $0 |
| **What it actually reproduces** | A **real** container calling the metadata endpoint gets **real** temporary credentials it can hand to the AWS SDK — the exact mechanism a task role uses in production. This is the first tool found in this entire project that reproduces task-role credential vesting as *real behavior*, not a mocked API response. |
| **What it does NOT reproduce** | ECS scheduling, health checks, ALB integration, autoscaling — it is metadata-endpoint-only |
| **Decision: ADAPT** | Wire it into a docker-compose stack alongside one of our existing Spring Boot apps (`serverless-api` is the natural fit) to observe a real task-role credential flow — directly closes the Phase 3 gap that execution-vs-task-role was "documented only." |

## Candidate 2 — nginx / Traefik as an ALB behavior stand-in
Not a specific repository — both are mature (nginx: BSD-2-Clause; Traefik: MIT), ubiquitous, and directly relevant.
| | |
|---|---|
| **What it actually reproduces** | Real reverse-proxy health checking against real backend containers. Stop a backend container → **real** 502/503 from the proxy. Fix a health-check path → **real** state transition to healthy. This is not AWS ALB, but it is **real load-balancer behavior**, not an API-shape simulation of one. |
| **What it does NOT reproduce** | AWS-specific ALB behavior (target-group deregistration delay, AWS-specific health-check semantics, IAM/SG integration) |
| **Decision: ADAPT** | A docker-compose lab (nginx/Traefik in front of 2 app containers) gives genuine BUILD→BREAK→OBSERVE→FIX cycles for "ALB returns 503" reasoning, at $0, before any real ALB is deployed in Phase 4. Clearly labeled as *behavior-equivalent*, not AWS-identical — per the "do not fake AWS behavior" rule, this must be documented as a **proxy for reasoning about the failure mode**, not a substitute for real ALB target-group/health-check semantics. |

## Candidate 3 — `getmoto/moto`
| | |
|---|---|
| Purpose | Python library mocking boto3/AWS API calls in-process |
| License | Apache-2.0 ✅ | Stars | 8,655 | Maintenance | pushed same day as this audit — extremely active |
| **What it actually reproduces** | API request/response shape, same category as Ministack. It does **not** run real containers for ECS, does **not** run a real database for RDS. |
| **Decision: DO NOT USE** for the ECS/ALB/RDS hands-on gap — same fidelity ceiling already proven insufficient. **Not relevant** to this stack either (Python-only; our app layer is Java/Spring). |

## Candidate 4 — chaos-on-aws / sample-devops-agent-ecs-workshop (already audited, re-confirmed here)
Both require **real ECS/RDS running in real AWS** — their `inject.sh` scripts call real `aws ecs`/`aws rds` APIs. **No local-hands-on value** until Phase 5/6 real infrastructure exists. Confirmed: **REFERENCE for design, ADAPT only once real AWS is live** — unchanged from Phase 3's conclusion, re-verified rather than assumed here.

## Candidate 5 — LocalStack (not Ministack) Community vs Pro
Not previously re-checked this session. LocalStack Community has the same category of limitation as Ministack for ECS/ALB/RDS (documented industry-wide); LocalStack **Pro** claims deeper ECS/RDS emulation but is a **paid** product — disqualifies it from the $0 constraint. **Decision: DO NOT USE** (Community — same fidelity ceiling; Pro — violates cost constraint).

## Summary decision table

| Repository | Capability | Runnable? | AWS required? | Cost | Fit | Decision |
|---|---|---|---|---|---|---|
| `amazon-ecs-local-container-endpoints` | real task-role credential vending | Yes | No | $0 | High — closes a real Phase 3 gap | **ADAPT** |
| nginx/Traefik | real reverse-proxy health-check/failover behavior | Yes | No | $0 | High — closes a real Phase 4 gap, labeled as behavior-proxy | **ADAPT** |
| `getmoto/moto` | API-shape mocking (Python) | Yes | No | $0 | None — same ceiling as Ministack, wrong language | **DO NOT USE** |
| `chaos-on-aws`, `sample-devops-agent-ecs-workshop` | real-AWS failure injection | Only against real AWS | Yes | Real spend | High, but only once ECS/RDS exist | **REFERENCE now, ADAPT at Phase 5/6** |
| LocalStack Community/Pro | ECS/ALB/RDS emulation | Community: same ceiling as Ministack. Pro: paid | — | Community $0 / Pro paid | Low | **DO NOT USE** |

**What this closes**: two genuine, currently-missing, zero-cost, *real-behavior* hands-on capabilities — task-role credential flow, and load-balancer health-check/failover behavior — without touching real AWS and without repeating the Ministack API-shape mistake.
