package com.interviewprep.connectivitytest.service;

import com.interviewprep.connectivitytest.config.AwsProperties;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;

@Service
public class S3HealthService {

    private final S3Client s3Client;
    private final String bucket;

    public S3HealthService(S3Client s3Client, AwsProperties props) {
        this.s3Client = s3Client;
        this.bucket = props.resources().bucket();
    }

    public String writeAndRead(String key, String content) {
        s3Client.putObject(
                PutObjectRequest.builder().bucket(bucket).key(key).build(),
                RequestBody.fromString(content, StandardCharsets.UTF_8));

        var response = s3Client.getObject(
                GetObjectRequest.builder().bucket(bucket).key(key).build());

        try {
            return new String(response.readAllBytes(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
