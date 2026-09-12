# Recommended Roadmap — Labs Replace Theory-First Phases

## The four modes, reassessed against actual hands-on capability (not repeated from prior design)

**LOCAL_MODE — redefined.** Previously meant "Ministack where verified + Terraform static analysis." That undersells what's actually available for $0: Docker + real Spring Boot apps (proven) + `amazon-ecs-local-container-endpoints` (real task-role credential flow) + nginx/Traefik (real health-check/failover behavior) + Terraform fmt/validate/test. LOCAL_MODE should be the primary mode for most of what remains of IAM/SG/ALB learning, not a fallback.

**CHEAP_MODE — unchanged in principle, newly urgent in practice.** Every VPC/routing/SG-enforcement/real-ECS/real-ALB/real-RDS behavior in `phase1/`–`phase3/` is currently unverified against real AWS. CHEAP_MODE is not optional scaffolding anymore — it is the only way to close the largest remaining gap (real network/IAM enforcement), and it has never been used once in this project.

**HA_MODE — correctly still dormant.** Nothing yet requires multi-AZ observation; no premature work needed here. Confirmed still appropriate to defer.

**CHAOS_MODE — correctly still dormant**, same reasoning — no real target exists yet to disrupt.

## Immediate retrofit (before Phase 4 starts)

A minimal viable hands-on pass over the existing IAM/SG/networking material, using what's already available:

**Lab R1 — Real task-role credential flow ($0, LOCAL_MODE)**
`amazon-ecs-local-container-endpoints` + `serverless-api` in docker-compose. Observe: a real credential fetch from the metadata endpoint, then break it (remove the endpoint from compose), observe the SDK call fail, restore, verify recovery. Closes Phase 3's single biggest gap — the execution-vs-task-role distinction has been reasoned about three times and observed zero times.

**Lab R2 — Real ALB-shaped failure ($0, LOCAL_MODE)**
nginx/Traefik in front of two app containers. Kill a backend → observe real 502/503. Break the health-check path → observe real unhealthy state. Fix, observe recovery. Explicitly labeled: *reproduces the failure-mode reasoning, not AWS ALB's exact semantics* — logged per the "do not fake AWS behavior" rule.

**Lab R3 — Minimal real VPC + SG (CHEAP_MODE, real AWS, smallest possible spend)**
Deploy only `modules/network` + `modules/security_groups` from Blueprint (not the full stack — no ALB/ECS/RDS yet). Real `terraform apply`, real `aws ec2 describe-*` verification, real SG-rule-removal-and-restore. This is the first real-AWS deployment in the entire project. Requires your explicit go-ahead and a cost/destroy-time commitment before it happens — nothing here authorizes it.

## Phase 4 (ALB) redesigned around labs, per the requested pattern

```
Lab 1: Deploy healthy ALB → ECS target → verify HTTP 200          [CHEAP_MODE, real AWS]
Lab 2: Break container port → observe ALB 503                      [real AWS]
Lab 3: Break health-check path → observe unhealthy target          [real AWS]
Lab 4: Block SG → observe health-check failure                     [real AWS]
Lab 5: Fix configuration → verify recovery                         [real AWS]
```
Theory documents (`alb-resource-chain.md`-style) remain, but strictly as **explanations of what Lab 1–5 produced**, written after execution — not predictions written before it.

## Every future phase, standing pattern
```
CONCEPT → EXISTING GITHUB SOLUTION? → REUSE/ADAPT/BUILD → RUN → OBSERVE → BREAK → INVESTIGATE → FIX → VERIFY → DOCUMENT
```
Documentation is the last step, describing what happened — not the first step, predicting what should happen.
