# Lab R1 — ECS Task Identity + IAM (real, $0)

Real ECS-style credential vending + real IAM ALLOW/DENY enforcement, entirely local.

## Reused (unmodified)
- `amazon/amazon-ecs-local-container-endpoints` (AWS-official) — the real ECS Task Metadata + Container Credentials protocol.
- `minio/minio` + `minio/mc` — real S3-compatible API with real policy-based authorization (genuine ALLOW/DENY, not an API-shape mock).

## Built (glue only)
`docker-compose.yml`, 3 provisioning scripts, 1 scenario runner, 1 terminal visualizer (~250 lines total, no framework). Visualization: searched GitHub first (see final report) — nothing fit a live per-request ALLOW/DENY flow, so the smallest possible layer was built: a colorized ANSI diagram, no server, no new dependency.

## What is real vs. not
**Real**: the metadata endpoint call, the vended credentials, MinIO's SigV4 signature check, MinIO's policy evaluation (ALLOW/DENY), the resulting S3 success/failure.
**Not AWS-identical**: MinIO's built-in users don't validate AWS STS session tokens the way real S3 does, so this lab's scenario script drops the vended session token before the S3 call and uses the real AccessKeyId/SecretAccessKey directly (see comment at the top of `scripts/run-scenario.sh`). Credential vending and IAM enforcement are both still fully real — only the STS session-token passthrough step is not exercised.

## Run it
```bash
docker compose up -d
bash scripts/run-scenario.sh baseline     # List ALLOW, Put ALLOW, Delete DENY
```

## Break it
```bash
MSYS_NO_PATHCONV=1 docker compose run --rm --entrypoint /bin/sh mc-init /scripts/break-iam.sh
bash scripts/run-scenario.sh break-observed   # Put now real AccessDenied
```

## Fix it (minimum permission only — not AdministratorAccess, not `*`)
```bash
MSYS_NO_PATHCONV=1 docker compose run --rm --entrypoint /bin/sh mc-init /scripts/fix-iam.sh
bash scripts/run-scenario.sh verify       # Put ALLOW again, Delete still DENY
```

## Tear down
```bash
docker compose down
```

## Diagnose (what the learner should be answering during "break")
Evidence is in `evidence/*.log` (raw request output) plus the visual flow printed after each step. Look at: which step changed from the baseline run, the exact MinIO error text (`AccessDenied` = IAM, not network — no network layer exists in this lab), and which policy file (`config/policies/*.json`) is currently attached (`mc admin policy attach ... --user TASKROLEACCESSKEY01`).

Full reuse audit, debugging journey, and what remains real-AWS-only: `R1-REPORT.md`.
