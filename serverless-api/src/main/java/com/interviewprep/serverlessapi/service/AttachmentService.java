package com.interviewprep.serverlessapi.service;

import com.interviewprep.serverlessapi.config.AwsProperties;
import com.interviewprep.serverlessapi.dto.PresignedUrlResponse;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;
import software.amazon.awssdk.services.s3.presigner.model.PresignedGetObjectRequest;
import software.amazon.awssdk.services.s3.presigner.model.PresignedPutObjectRequest;
import software.amazon.awssdk.services.s3.presigner.model.PutObjectPresignRequest;

import java.time.Duration;

/**
 * Generates presigned URLs so clients upload/download attachments directly to/from S3 —
 * the API never proxies file bytes, matching how a real API Gateway + Lambda design avoids
 * routing large payloads through the Lambda invocation itself.
 */
@Service
public class AttachmentService {

    private static final Duration URL_TTL = Duration.ofMinutes(15);

    private final S3Presigner presigner;
    private final String bucket;

    public AttachmentService(S3Presigner presigner, AwsProperties props) {
        this.presigner = presigner;
        this.bucket = props.resources().attachmentsBucket();
    }

    public PresignedUrlResponse presignUpload(String taskId, String fileName) {
        String key = "tasks/%s/%s".formatted(taskId, fileName);
        PutObjectRequest objectRequest = PutObjectRequest.builder()
                .bucket(bucket)
                .key(key)
                .build();
        PutObjectPresignRequest presignRequest = PutObjectPresignRequest.builder()
                .signatureDuration(URL_TTL)
                .putObjectRequest(objectRequest)
                .build();
        PresignedPutObjectRequest presigned = presigner.presignPutObject(presignRequest);
        return new PresignedUrlResponse(presigned.url().toString(), key, URL_TTL.toSeconds());
    }

    public PresignedUrlResponse presignDownload(String key) {
        GetObjectRequest objectRequest = GetObjectRequest.builder()
                .bucket(bucket)
                .key(key)
                .build();
        GetObjectPresignRequest presignRequest = GetObjectPresignRequest.builder()
                .signatureDuration(URL_TTL)
                .getObjectRequest(objectRequest)
                .build();
        PresignedGetObjectRequest presigned = presigner.presignGetObject(presignRequest);
        return new PresignedUrlResponse(presigned.url().toString(), key, URL_TTL.toSeconds());
    }
}
