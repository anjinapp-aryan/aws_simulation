package com.interviewprep.eventpipeline.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.enhanced.dynamodb.DynamoDbEnhancedClient;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.sns.SnsClient;
import software.amazon.awssdk.services.sqs.SqsClient;

import java.net.URI;

/**
 * Plain AWS SDK v2 clients (Version B path: EventPublisher, SqsPollingConsumer, S3 archive,
 * DynamoDB repository). Spring Cloud AWS's own SqsAsyncClient/SqsTemplate (Version A path) is
 * autoconfigured separately from spring.cloud.aws.* properties — see application.yml.
 */
@Configuration
public class AwsClientConfig {

    private final AwsProperties props;

    public AwsClientConfig(AwsProperties props) {
        this.props = props;
    }

    private boolean isLocal() {
        return props.endpointOverride() != null && !props.endpointOverride().isBlank();
    }

    private AwsCredentialsProvider credentialsProvider() {
        if (isLocal()) {
            return StaticCredentialsProvider.create(
                    AwsBasicCredentials.create(props.accessKey(), props.secretKey()));
        }
        return DefaultCredentialsProvider.create();
    }

    @Bean
    public SqsClient sqsClient() {
        var builder = SqsClient.builder()
                .region(Region.of(props.region()))
                .credentialsProvider(credentialsProvider());
        if (isLocal()) {
            builder.endpointOverride(URI.create(props.endpointOverride()));
        }
        return builder.build();
    }

    @Bean
    public SnsClient snsClient() {
        var builder = SnsClient.builder()
                .region(Region.of(props.region()))
                .credentialsProvider(credentialsProvider());
        if (isLocal()) {
            builder.endpointOverride(URI.create(props.endpointOverride()));
        }
        return builder.build();
    }

    @Bean
    public S3Client s3Client() {
        var builder = S3Client.builder()
                .region(Region.of(props.region()))
                .credentialsProvider(credentialsProvider())
                .forcePathStyle(isLocal());
        if (isLocal()) {
            builder.endpointOverride(URI.create(props.endpointOverride()));
        }
        return builder.build();
    }

    @Bean
    public DynamoDbClient dynamoDbClient() {
        var builder = DynamoDbClient.builder()
                .region(Region.of(props.region()))
                .credentialsProvider(credentialsProvider());
        if (isLocal()) {
            builder.endpointOverride(URI.create(props.endpointOverride()));
        }
        return builder.build();
    }

    @Bean
    public DynamoDbEnhancedClient dynamoDbEnhancedClient(DynamoDbClient dynamoDbClient) {
        return DynamoDbEnhancedClient.builder().dynamoDbClient(dynamoDbClient).build();
    }
}
