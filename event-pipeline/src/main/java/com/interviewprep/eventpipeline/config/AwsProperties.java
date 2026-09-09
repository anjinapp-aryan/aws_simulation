package com.interviewprep.eventpipeline.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "aws")
public record AwsProperties(
        String region,
        String endpointOverride,
        String accessKey,
        String secretKey,
        Resources resources
) {
    public record Resources(String topic, String queue, String dlq, String table, String archiveBucket) {
    }
}
