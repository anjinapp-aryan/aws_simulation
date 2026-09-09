package com.interviewprep.eventpipeline.service;

import com.interviewprep.eventpipeline.config.AwsProperties;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

import java.nio.charset.StandardCharsets;
import java.time.Instant;

/** Archives every raw event to S3 for replay/audit — independent of whether DynamoDB processing succeeds. */
@Service
public class EventArchiveService {

    private final S3Client s3Client;
    private final String bucket;

    public EventArchiveService(S3Client s3Client, AwsProperties props) {
        this.s3Client = s3Client;
        this.bucket = props.resources().archiveBucket();
    }

    public void archive(String orderId, String rawPayload) {
        String key = "order-events/%s/%s.json".formatted(orderId, Instant.now().toEpochMilli());
        s3Client.putObject(
                PutObjectRequest.builder().bucket(bucket).key(key).build(),
                RequestBody.fromString(rawPayload, StandardCharsets.UTF_8));
    }
}
