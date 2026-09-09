package com.interviewprep.connectivitytest.service;

import com.interviewprep.connectivitytest.config.AwsProperties;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.sns.SnsClient;
import software.amazon.awssdk.services.sns.model.ListTopicsResponse;
import software.amazon.awssdk.services.sns.model.PublishRequest;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.GetQueueUrlRequest;
import software.amazon.awssdk.services.sqs.model.Message;
import software.amazon.awssdk.services.sqs.model.ReceiveMessageRequest;

import java.util.List;

/**
 * SNS fans out to the SQS queue (subscription created by init-ministack.sh),
 * so publishing to the topic and polling the queue exercises both services together.
 */
@Service
public class MessagingHealthService {

    private final SnsClient snsClient;
    private final SqsClient sqsClient;
    private final String topicName;
    private final String queueName;

    public MessagingHealthService(SnsClient snsClient, SqsClient sqsClient, AwsProperties props) {
        this.snsClient = snsClient;
        this.sqsClient = sqsClient;
        this.topicName = props.resources().topic();
        this.queueName = props.resources().queue();
    }

    public String publish(String message) {
        String topicArn = findTopicArn();
        var result = snsClient.publish(PublishRequest.builder()
                .topicArn(topicArn)
                .message(message)
                .build());
        return result.messageId();
    }

    public List<String> pollQueue() {
        String queueUrl = sqsClient.getQueueUrl(
                GetQueueUrlRequest.builder().queueName(queueName).build()).queueUrl();

        var response = sqsClient.receiveMessage(ReceiveMessageRequest.builder()
                .queueUrl(queueUrl)
                .maxNumberOfMessages(10)
                .waitTimeSeconds(2)
                .build());

        return response.messages().stream().map(Message::body).toList();
    }

    private String findTopicArn() {
        ListTopicsResponse topics = snsClient.listTopics();
        return topics.topics().stream()
                .map(t -> t.topicArn())
                .filter(arn -> arn.contains(topicName))
                .findFirst()
                .orElseThrow(() -> new IllegalStateException("Topic not found: " + topicName));
    }
}
