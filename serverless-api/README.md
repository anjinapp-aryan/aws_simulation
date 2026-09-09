# Project A — Serverless Task API

API-Gateway + Lambda-style REST service: Spring Boot for local dev/testing (runs as a normal
process here so it's trivial to iterate on), backed by DynamoDB (task records) and S3
(attachments, via presigned URLs so the app never proxies file bytes).

## Architecture

```
Client --HTTP--> [Spring Boot / API Gateway+Lambda]
                        |
                        +--> DynamoDB (TasksTable)      -- task CRUD
                        +--> S3 (task-attachments-bucket) -- presigned upload/download URLs only
```

- **Why presigned URLs, not proxy-through-Lambda**: routing file bytes through an API
  Gateway + Lambda invocation burns Lambda duration and hits the 6MB payload limit. Presigned
  PUT/GET URLs let the client talk to S3 directly; the API only issues short-lived (15 min)
  signed URLs.
- **Optimistic locking**: `Task.version` (`@DynamoDbVersionAttribute`) — the enhanced client
  auto-increments and conditions `updateItem` on it, so concurrent PUTs fail loud instead of
  silently clobbering each other. Good interview talking point on race conditions in DynamoDB.

## Failure modes worth knowing for an interview

- **DynamoDB throttling**: PAY_PER_REQUEST here avoids capacity planning, but a real hot
  partition (e.g. everyone hitting one task id) still throttles — mitigate with better key
  design or DAX caching.
- **Presigned URL abuse**: anyone with the URL can upload within the TTL window — for real AWS,
  scope the bucket policy tightly and consider virus-scanning uploads via S3 event -> Lambda.
- **Lambda cold starts** (once deployed as Lambda): JVM cold start is the classic Java-on-Lambda
  pain point — mitigate with SnapStart, smaller deployment package, or provisioned concurrency.

## Run locally

```bash
# 1. Ministack up (from repo root)
docker compose up -d ministack

# 2. Provision resources
cd serverless-api/terraform
terraform init
terraform apply -auto-approve

# 3. Run the app
cd ..
AWS_ENDPOINT_URL=http://localhost:4566 AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
  ./mvnw spring-boot:run
```

## Try it

```bash
curl -X POST http://localhost:8082/tasks -H 'Content-Type: application/json' \
  -d '{"title":"Prep AWS interview","description":"Review DynamoDB partition design"}'

curl http://localhost:8082/tasks

curl -X POST "http://localhost:8082/tasks/<id>/attachments/upload-url?fileName=notes.pdf"
```

## Tests

```bash
./mvnw test                    # unit tests (TaskServiceTest, mocked repository)
./mvnw test -Dtest=TaskApiIT   # integration test, needs Ministack + terraform apply done
```

Note: on very new JDKs (25+) Mockito's inline mock maker can fail to self-attach — this
project was verified on JDK 21. If your default JDK is newer, point `JAVA_HOME` at a 21
install for `./mvnw test`.

## Deploying to real AWS

- `terraform apply -var-file=aws.tfvars` — same resources, drops the Ministack endpoint
  overrides.
- App: `SPRING_PROFILES_ACTIVE=aws`, unset `AWS_ENDPOINT_URL`, real credentials via env/IAM role.
- To go fully serverless: wrap `ServerlessApiApplication` with
  `aws-serverless-java-container-springboot3` and deploy behind API Gateway + Lambda instead of
  running Tomcat — the service/repository/controller code doesn't change, only the entry point.
