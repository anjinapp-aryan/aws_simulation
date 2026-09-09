# Project B — Event-Driven Order Pipeline

`POST /orders` publishes an `OrderCreatedEvent` to SNS. SNS fans out to an SQS queue with a
dead-letter queue. A consumer processes the queue, writes the order to DynamoDB, and archives
the raw event to S3 for replay/audit — independent of whether DynamoDB processing succeeds.

```
POST /orders --> SNS (order-events-topic)
                    |
                    v
              SQS (order-processing-queue) --3 failed attempts--> SQS DLQ (order-processing-dlq)
                    |
                    v
         [Consumer: plain-SDK poll OR Spring Cloud AWS @SqsListener]
                    |
        +-----------+-----------+
        v                       v
  DynamoDB (OrdersTable)   S3 (order-events-archive, always)
```

## Why SNS -> SQS, not producer -> SQS directly

SNS fan-out means new consumers (analytics, notifications, a future audit service) can
subscribe their own queue to the same topic later without the producer changing at all —
classic pub/sub decoupling. Direct-to-SQS would mean every new consumer requires a producer
change.

## Two consumer implementations, same business logic

Both call the same `OrderProcessingService` — only the SQS plumbing differs, toggled by
`pipeline.consumer.mode`:

| | Version B: `SqsPollingConsumer` (plain SDK v2) | Version A: `SqsListenerConsumer` (Spring Cloud AWS) |
|---|---|---|
| Mechanism | `@Scheduled` long-poll loop, manual `receiveMessage`/`deleteMessage` | `@SqsListener` annotation, framework-managed |
| Retry/DLQ | Implicit: don't delete on failure -> message revisits after visibility timeout -> DLQ after `maxReceiveCount` | Same SQS-level mechanism, but you don't write the receive/delete loop yourself |
| Control | Full visibility into exactly when messages are deleted, batch size, wait time | Less boilerplate, but less control (framework decides polling internals) |
| When to reach for it | Need custom batching/backpressure logic, or want zero extra dependencies | Team already standardized on Spring Cloud AWS; want less plumbing code |

Switch with `pipeline.consumer.mode=plain-sdk` (default) or `spring-cloud-aws`, e.g.:
```bash
./mvnw spring-boot:run -Dspring-boot.run.arguments=--pipeline.consumer.mode=spring-cloud-aws
```

## Failure mode: poison messages

Send an event with `quantity=0` or `amount=0` and `OrderProcessingService` throws
`IllegalArgumentException`. Neither consumer deletes the message on failure, so SQS makes it
visible again after the visibility timeout (30s) and retries — after `max_receive_count` (3,
set in Terraform) failed deliveries, SQS auto-moves it to the DLQ. Verified locally: a
malformed event published directly to SNS landed in `order-processing-dlq` after exactly 3
logged `IllegalArgumentException`s.

Real-world handling from here: a CloudWatch alarm on DLQ depth, a small reprocessing tool to
replay/fix DLQ messages, and (since raw events are archived to S3 regardless of processing
outcome) full audit trail even for messages that never made it to DynamoDB.

## Run locally

```bash
# 1. Ministack up (from repo root)
docker compose up -d ministack

# 2. Provision resources (SNS topic, SQS queue+DLQ, DynamoDB table, S3 bucket)
cd event-pipeline/terraform
terraform init
terraform apply -auto-approve

# 3. Run the app
cd ..
AWS_ENDPOINT_URL=http://localhost:4566 AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
  ./mvnw spring-boot:run
```

## Try it

```bash
curl -X POST http://localhost:8083/orders -H 'Content-Type: application/json' \
  -d '{"customerId":"cust-1","item":"Mechanical Keyboard","quantity":2,"amount":149.99}'
# -> {"orderId":"...", "snsMessageId":"...", "status":"ACCEPTED"}

curl http://localhost:8083/orders/<orderId>
# -> {"status":"PROCESSED", ...} once the consumer picks it up (~3s poll interval)
```

## Tests

```bash
./mvnw test                        # unit test: OrderProcessingServiceTest (mocked repo/archive)
./mvnw test -Dtest=OrderPipelineIT # integration test: full HTTP -> SNS -> SQS -> DynamoDB, needs Ministack + terraform apply
```

Same JDK 21 note as the other projects — Mockito's inline mock maker needs it if your default
JDK is newer.

## Deploying to real AWS

- `terraform apply -var-file=aws.tfvars` — same resources, drops Ministack endpoint overrides.
- App: `SPRING_PROFILES_ACTIVE=aws`, unset `AWS_ENDPOINT_URL`, real credentials via env/IAM role.
- To go fully event-driven/serverless: replace the Spring Boot consumer with a Lambda subscribed
  directly to the SQS queue (event source mapping) — `OrderProcessingService` is framework-agnostic
  and can be called from a Lambda handler unchanged.

## Interview questions this project answers well

1. Why SNS fan-out to SQS instead of a direct producer-to-consumer coupling?
2. How does a message end up on a DLQ, and what's `maxReceiveCount` actually doing?
3. Why archive raw events to S3 separately from the "processed" DynamoDB write?
4. Plain SDK polling vs `@SqsListener` — what do you give up/gain with each?
5. What happens if two consumer instances run concurrently — does a message get processed twice?
   (SQS visibility timeout prevents double-delivery within the window, but at-least-once delivery
   means your processing must be idempotent — this implementation's `putItem` is a blind
   overwrite, which is idempotent by accident; discuss what wouldn't be, e.g. an increment.)
6. How would you monitor this in production? (DLQ depth alarm, queue age/backlog, Lambda/consumer
   error rate, S3 archive completeness vs DynamoDB record count as a reconciliation check.)
7. Cost/scaling trade-offs: polling consumer on a fixed schedule vs event-driven Lambda vs
   Spring Cloud AWS's own concurrency settings.
