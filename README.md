# AWS Interview Prep — Local Simulation with Ministack

Repo layout:
- `connectivity-test/` — health-check app hitting S3, DynamoDB, SQS/SNS, Kinesis (Part 1)
- `serverless-api/` — Project A: Task Management API, DynamoDB + S3 presigned URLs (own [README](serverless-api/README.md))
- `event-pipeline/` — Project B: Order event pipeline, SNS->SQS(+DLQ)->DynamoDB/S3, plain-SDK vs Spring Cloud AWS consumers (own [README](event-pipeline/README.md))
- `terraform/`, `serverless-api/terraform/`, `event-pipeline/terraform/` — each project's infra, separate state

## 1. Start Ministack

```bash
docker compose up -d ministack
```

Verify it's healthy:
```bash
curl http://localhost:4566/_ministack/health
```

## 2. Create AWS resources with Terraform (S3 bucket, DynamoDB table, SQS queue, SNS topic + subscription, Kinesis stream)

```bash
cd terraform
terraform init
terraform apply -auto-approve   # defaults to use_local_endpoints = true (Ministack)
```

Requires Terraform >= 1.7 (`choco install terraform` on Windows).

## 3. Run the connectivity-test Spring Boot app

Locally (WSL2 or PowerShell, Maven installed):
```bash
cd connectivity-test
./mvnw spring-boot:run
# or on Windows: mvnw.cmd spring-boot:run
```

Or via Docker Compose (builds + runs against Ministack automatically):
```bash
docker compose up -d --build
```

## 4. Exercise the endpoints

```bash
curl http://localhost:8081/health-check/s3
curl http://localhost:8081/health-check/dynamodb
curl http://localhost:8081/health-check/messaging
curl http://localhost:8081/health-check/kinesis
curl http://localhost:8081/health-check/all
```

## Switching to real AWS

Infra: `terraform apply -var-file=aws.tfvars` (see `terraform/aws.tfvars.example`) — same
resource blocks, provider drops the Ministack endpoint overrides and uses the default AWS
credential chain instead.

App: set `SPRING_PROFILES_ACTIVE=aws`, unset `AWS_ENDPOINT_URL`, and provide real credentials via
env vars / `~/.aws/credentials` / IAM role. `AwsClientConfig` picks `DefaultCredentialsProvider`
and drops the endpoint override automatically — no code change needed.

## Notes on Ministack

- LocalStack-compatible: single edge port 4566, same AWS CLI/SDK endpoint pattern.
- Emulates 60+ services (S3, DynamoDB, SQS, SNS, Kinesis, Lambda, API Gateway, EventBridge, etc.).
- Free, MIT licensed, Python-based, ~270MB Docker image, actively maintained (4.6k stars).
- Ministack's in-memory state resets on container recreation (`docker compose down && up`), even
  with the `ministack-data` volume attached — re-run `terraform apply` after a reset.

## Toolchain notes (this environment)

- Mockito's inline mock maker fails to self-attach on very new JDKs (25+ as of this writing).
  Point `JAVA_HOME` at a JDK 21 install when running `mvn test` if your default JDK is newer.
- No system Terraform install here — a portable `terraform.exe` was downloaded to `.tools/`
  (gitignored) as a workaround for a blocked `choco install` elevation prompt. Install Terraform
  properly (`choco install terraform -y` or winget) when convenient.
