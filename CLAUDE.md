# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Two independent tracks living side by side:

1. **Application-layer AWS simulation** (`connectivity-test/`, `serverless-api/`, `event-pipeline/`) — three real Spring Boot 3.3.4 / Java 21 services exercising S3, DynamoDB, SQS, SNS, Kinesis against **Ministack** (a LocalStack-compatible local AWS emulator, single edge port 4566). Each has its own Terraform root. Real, tested, verified working end-to-end (including a real SQS DLQ poison-message redrive).
2. **Infrastructure-layer AWS/Terraform learning simulation** (`phase1/`, `phase2/`, `phase3/`, `phase-audit/`, `r3/`, `labs/`, `candidates/`) — a separate, deliberately hands-on-first learning project built around a vendored reference Terraform codebase and a series of local Docker-based "labs" that reproduce real (not mocked) AWS-adjacent behavior. This track has no architectural overlap with track 1.

These two tracks are unrelated in content; don't try to unify them.

## Track 1 — Application-layer (Java/Spring/Terraform)

### Commands
```bash
# Start the local AWS emulator (from repo root)
docker compose up -d ministack
curl http://localhost:4566/_ministack/health   # verify healthy

# Per-module: provision infra, then run the app
cd <connectivity-test|serverless-api|event-pipeline>
cd terraform && terraform init && terraform apply -auto-approve && cd ..
./mvnw spring-boot:run          # mvnw.cmd on native Windows shells
./mvnw test                     # unit tests
./mvnw test -Dtest=<ClassName>  # single test
./mvnw test -Dtest=<ClassName>IT   # integration test (needs Ministack up + terraform applied first; self-skips otherwise)
```
Ports: connectivity-test `8081`, serverless-api `8082`, event-pipeline `8083`.

Root `docker-compose.yml` also builds/runs all three apps in containers (`docker compose up -d --build`), wired to the same `ministack` service.

### Architecture
- All three modules share one package convention: `com.interviewprep.<module>.{config,web,service,repository,model,dto}` (event-pipeline adds `consumer/`, `publisher/`).
- **`AwsClientConfig`** in each module is the key file to read first — a single `isLocal()` check (true when `aws.endpoint-override` is non-blank) decides both the credentials provider (`StaticCredentialsProvider` test/test vs `DefaultCredentialsProvider`) and whether an endpoint override is set. Spring profile `local` (default) targets Ministack; profile `aws` drops the override and uses the real default credential chain — no code change needed to go from local to real AWS, only `SPRING_PROFILES_ACTIVE` and env vars.
- `event-pipeline` demonstrates both plain AWS SDK v2 (`SqsPollingConsumer`) and Spring Cloud AWS (`SqsListenerConsumer`) consuming the same queue — toggle via `pipeline.consumer.mode` (`plain-sdk` default, or `spring-cloud-aws`).
- Terraform roots (`terraform/`, `*/terraform/`) each have a `use_local_endpoints` var (default `true`, targets Ministack) and an `aws.tfvars.example` for pointing at real AWS instead.

### Known environment quirks (Windows/Git Bash/Ministack)
- Ministack's state resets on container recreation even with its data volume attached — re-run `terraform apply` after any `docker compose down && up`.
- Mockito's inline mock maker fails to self-attach on JDK 25+; point `JAVA_HOME` at a JDK 21 install for `mvn test` if the default JDK is newer.
- No system Terraform install in this environment — a portable `terraform.exe` lives in `.tools/` (gitignored).
- Git Bash mangles Unix-style absolute paths (`/tmp/...`, `/bin/sh`) passed as CLI args to `docker ... exec`/`run --entrypoint`; set `MSYS_NO_PATHCONV=1` before such commands.
- Docker credential-helper errors (`docker-credential-desktop not found`) are fixed by removing the `credsStore` key from `~/.docker/config.json` — safe for these public, unauthenticated image pulls.

## Track 2 — Infrastructure learning simulation

### What's real vs. reference-only
- `candidates/` is **vendored, gitignored, read-only reference material** — cloned third-party repos (primarily `AWS-ECS-Blueprint`, plus several others) used as the canonical Terraform learning codebase and as GitHub-reuse-audit candidates. Never treat it as this project's own code; don't commit to it.
- `phase1/`–`phase3/`, `phase-audit/` are Markdown analysis/audit deliverables (Terraform read, tested via `fmt`/`validate`/`test`, but not applied to real AWS).
- `r3/` and `labs/R1-*`, `labs/R2-*`, `labs/r3-*` are **runnable, $0, local Docker simulations** — the project's actual hands-on deliverables. Each lab directory is self-contained with its own `docker-compose.yml`, `scripts/`, and a `*-REPORT.md` documenting what was actually run, broken, and fixed (not predicted).

### Standing project methodology (applies to any new lab/phase in this track)
```
CONCEPT → GitHub reuse audit (REUSE > ADAPT > REFERENCE > BUILD) → RUN → OBSERVE → BREAK → INVESTIGATE → FIX → VERIFY → DOCUMENT
```
- Reuse mature existing tools before building anything (established stack across labs: Traefik for ALB-behavior/routing+health-check visualization, `amazon-ecs-local-container-endpoints` for real ECS-style task-credential vending, `registry:2` for a real local ECR-equivalent, Dozzle for real-time container logs). Custom code per lab has stayed to a few hundred lines of glue at most.
- Every claimed behavior must be **actually executed and observed**, not asserted — evidence (timestamps, command output, `docker inspect` state) is captured in each lab's `evidence/` dir and report.
- Every simulated component gets an explicit fidelity label: **REAL** / **BEHAVIOR-EQUIVALENT** / **NOT REPRODUCIBLE LOCALLY** (e.g. Ministack was empirically proven to give real behavior for S3/DynamoDB/SQS/SNS/Kinesis but to be an API-shape-only mock for ECS/ALB/RDS — verified by starting real containers and checking whether they actually ran, not by reading its docs).
- Target AWS spend for this track is $0 unless a specific lab explicitly says otherwise and has been approved; no `terraform apply` against real AWS has occurred in this track.
