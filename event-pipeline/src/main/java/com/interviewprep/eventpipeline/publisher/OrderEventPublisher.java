package com.interviewprep.eventpipeline.publisher;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.interviewprep.eventpipeline.config.AwsProperties;
import com.interviewprep.eventpipeline.dto.OrderCreatedEvent;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.services.sns.SnsClient;
import software.amazon.awssdk.services.sns.model.ListTopicsResponse;
import software.amazon.awssdk.services.sns.model.PublishRequest;

/**
 * Publishes to SNS, not directly to SQS — SNS fan-out means other consumers (analytics,
 * notifications) can subscribe their own queues later without the producer changing at all.
 */
@Component
public class OrderEventPublisher {

    private final SnsClient snsClient;
    private final ObjectMapper objectMapper;
    private final String topicName;
    private String cachedTopicArn;

    public OrderEventPublisher(SnsClient snsClient, ObjectMapper objectMapper, AwsProperties props) {
        this.snsClient = snsClient;
        this.objectMapper = objectMapper;
        this.topicName = props.resources().topic();
    }

    public String publish(OrderCreatedEvent event) {
        try {
            String payload = objectMapper.writeValueAsString(event);
            var result = snsClient.publish(PublishRequest.builder()
                    .topicArn(topicArn())
                    .message(payload)
                    .build());
            return result.messageId();
        } catch (Exception e) {
            throw new RuntimeException("Failed to publish order event", e);
        }
    }

    private String topicArn() {
        if (cachedTopicArn == null) {
            ListTopicsResponse topics = snsClient.listTopics();
            cachedTopicArn = topics.topics().stream()
                    .map(t -> t.topicArn())
                    .filter(arn -> arn.contains(topicName))
                    .findFirst()
                    .orElseThrow(() -> new IllegalStateException("Topic not found: " + topicName));
        }
        return cachedTopicArn;
    }
}
