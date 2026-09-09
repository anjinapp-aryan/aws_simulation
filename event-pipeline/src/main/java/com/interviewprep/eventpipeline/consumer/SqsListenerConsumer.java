package com.interviewprep.eventpipeline.consumer;

import com.interviewprep.eventpipeline.service.OrderProcessingService;
import io.awspring.cloud.sqs.annotation.SqsListener;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

/**
 * Version A: Spring Cloud AWS annotation-driven consumer.
 * Same business logic as SqsPollingConsumer (OrderProcessingService) — only the plumbing
 * differs. Throwing here is enough to trigger Spring Cloud AWS's retry/DLQ handling; no manual
 * receive/delete/visibility-timeout bookkeeping.
 */
@Component
@ConditionalOnProperty(prefix = "pipeline.consumer", name = "mode", havingValue = "spring-cloud-aws")
public class SqsListenerConsumer {

    private static final Logger log = LoggerFactory.getLogger(SqsListenerConsumer.class);

    private final OrderProcessingService processingService;

    public SqsListenerConsumer(OrderProcessingService processingService) {
        this.processingService = processingService;
        log.info("SqsListenerConsumer active (pipeline.consumer.mode=spring-cloud-aws)");
    }

    @SqsListener("${aws.resources.queue}")
    public void onMessage(String messageBody) throws Exception {
        processingService.process(messageBody);
    }
}
