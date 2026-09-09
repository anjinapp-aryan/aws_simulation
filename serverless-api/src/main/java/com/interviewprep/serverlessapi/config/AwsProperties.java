package com.interviewprep.serverlessapi.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "aws")
public record AwsProperties(
        String region,
        String endpointOverride,
        String accessKey,
        String secretKey,
        Resources resources
) {
    public record Resources(String table, String attachmentsBucket) {
    }
}
