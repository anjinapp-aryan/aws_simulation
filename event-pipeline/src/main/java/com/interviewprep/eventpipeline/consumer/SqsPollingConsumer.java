package com.interviewprep.eventpipeline.consumer;

import com.interviewprep.eventpipeline.config.AwsProperties;
import com.interviewprep.eventpipeline.service.OrderProcessingService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.DeleteMessageRequest;
import software.amazon.awssdk.services.sqs.model.GetQueueUrlRequest;
import software.amazon.awssdk.services.sqs.model.Message;
import software.amazon.awssdk.services.sqs.model.ReceiveMessageRequest;

/**
 * Version B: plain AWS SDK v2 long-polling consumer.
 * Explicit control over receive/delete — you see exactly where retries and visibility timeout
 * come from, which is the point of showing this next to the Spring Cloud AWS version.
 */
@Component
@ConditionalOnProperty(prefix = "pipeline.consumer", name = "mode", havingValue = "plain-sdk", matchIfMissing = true)
public class SqsPollingConsumer {

    private static final Logger log = LoggerFactory.getLogger(SqsPollingConsumer.class);

    private final SqsClient sqsClient;
    private final OrderProcessingService processingService;
    private final String queueName;
    private String cachedQueueUrl;

    public SqsPollingConsumer(SqsClient sqsClient, OrderProcessingService processingService, AwsProperties props) {
        this.sqsClient = sqsClient;
        this.processingService = processingService;
        this.queueName = props.resources().queue();
        log.info("SqsPollingConsumer active (pipeline.consumer.mode=plain-sdk)");
    }

    @Scheduled(fixedDelay = 3000)
    public void poll() {
        String queueUrl = queueUrl();
        var response = sqsClient.receiveMessage(ReceiveMessageRequest.builder()
                .queueUrl(queueUrl)
                .maxNumberOfMessages(10)
                .waitTimeSeconds(5)
                .build());

        for (Message message : response.messages()) {
            try {
                processingService.process(message.body());
                sqsClient.deleteMessage(DeleteMessageRequest.builder()
                        .queueUrl(queueUrl)
                        .receiptHandle(message.receiptHandle())
                        .build());
            } catch (Exception e) {
                // Do not delete: message becomes visible again after the visibility timeout and
                // is retried, up to the queue's maxReceiveCount, then routed to the DLQ.
                log.error("Failed to process message {}, leaving for retry/DLQ", message.messageId(), e);
            }
        }
    }

    private String queueUrl() {
        if (cachedQueueUrl == null) {
            cachedQueueUrl = sqsClient.getQueueUrl(
                    GetQueueUrlRequest.builder().queueName(queueName).build()).queueUrl();
        }
        return cachedQueueUrl;
    }
}
