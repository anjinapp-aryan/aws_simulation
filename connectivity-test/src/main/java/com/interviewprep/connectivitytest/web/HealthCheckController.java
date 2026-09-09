package com.interviewprep.connectivitytest.web;

import com.interviewprep.connectivitytest.service.DynamoDbHealthService;
import com.interviewprep.connectivitytest.service.KinesisHealthService;
import com.interviewprep.connectivitytest.service.MessagingHealthService;
import com.interviewprep.connectivitytest.service.S3HealthService;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/health-check")
public class HealthCheckController {

    private final S3HealthService s3HealthService;
    private final DynamoDbHealthService dynamoDbHealthService;
    private final MessagingHealthService messagingHealthService;
    private final KinesisHealthService kinesisHealthService;

    public HealthCheckController(S3HealthService s3HealthService,
                                  DynamoDbHealthService dynamoDbHealthService,
                                  MessagingHealthService messagingHealthService,
                                  KinesisHealthService kinesisHealthService) {
        this.s3HealthService = s3HealthService;
        this.dynamoDbHealthService = dynamoDbHealthService;
        this.messagingHealthService = messagingHealthService;
        this.kinesisHealthService = kinesisHealthService;
    }

    @GetMapping("/s3")
    public Map<String, String> s3() {
        String key = "health-check/" + UUID.randomUUID() + ".txt";
        String content = s3HealthService.writeAndRead(key, "hello from spring boot at " + java.time.Instant.now());
        return Map.of("key", key, "content", content);
    }

    @GetMapping("/dynamodb")
    public Map<String, String> dynamoDb() {
        String id = UUID.randomUUID().toString();
        return dynamoDbHealthService.writeAndRead(id, "hello from dynamodb health check");
    }

    @GetMapping("/messaging")
    public Map<String, Object> messaging() {
        String messageId = messagingHealthService.publish("hello via sns -> sqs at " + java.time.Instant.now());
        List<String> received = messagingHealthService.pollQueue();
        return Map.of("publishedMessageId", messageId, "receivedFromQueue", received);
    }

    @GetMapping("/kinesis")
    public Map<String, Object> kinesis() {
        String sequenceNumber = kinesisHealthService.putRecord("partition-1", "hello from kinesis health check");
        List<String> records = kinesisHealthService.readLatestRecords();
        return Map.of("sequenceNumber", sequenceNumber, "records", records);
    }

    @GetMapping("/all")
    public Map<String, Object> all() {
        return Map.of(
                "s3", s3(),
                "dynamodb", dynamoDb(),
                "messaging", messaging(),
                "kinesis", kinesis()
        );
    }
}
