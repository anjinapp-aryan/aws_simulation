package com.interviewprep.eventpipeline.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.interviewprep.eventpipeline.dto.OrderCreatedEvent;
import com.interviewprep.eventpipeline.model.OrderRecord;
import com.interviewprep.eventpipeline.repository.OrderRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.time.Instant;

/**
 * Shared by both consumer implementations (plain-SDK polling and Spring Cloud AWS @SqsListener)
 * so the business logic — and its failure behavior — is identical regardless of which one is active.
 */
@Service
public class OrderProcessingService {

    private static final Logger log = LoggerFactory.getLogger(OrderProcessingService.class);

    private final ObjectMapper objectMapper;
    private final OrderRepository orderRepository;
    private final EventArchiveService archiveService;

    public OrderProcessingService(ObjectMapper objectMapper, OrderRepository orderRepository,
                                   EventArchiveService archiveService) {
        this.objectMapper = objectMapper;
        this.orderRepository = orderRepository;
        this.archiveService = archiveService;
    }

    /**
     * @param sqsMessageBody raw SQS message body — an SNS notification envelope whose "Message"
     *                       field holds the JSON-encoded OrderCreatedEvent.
     */
    public void process(String sqsMessageBody) throws Exception {
        JsonNode envelope = objectMapper.readTree(sqsMessageBody);
        String innerMessage = envelope.has("Message") ? envelope.get("Message").asText() : sqsMessageBody;

        archiveService.archive(extractOrderIdBestEffort(innerMessage), innerMessage);

        OrderCreatedEvent event = objectMapper.readValue(innerMessage, OrderCreatedEvent.class);
        if (event.quantity() <= 0 || event.amount() <= 0) {
            // Deliberately fails processing on bad data -> message becomes visible again,
            // retries up to maxReceiveCount, then lands on the DLQ for inspection.
            throw new IllegalArgumentException("Invalid order event: " + event);
        }

        OrderRecord record = new OrderRecord();
        record.setOrderId(event.orderId());
        record.setCustomerId(event.customerId());
        record.setItem(event.item());
        record.setQuantity(event.quantity());
        record.setAmount(event.amount());
        record.setStatus("PROCESSED");
        record.setProcessedAt(Instant.now().toString());
        orderRepository.save(record);

        log.info("Processed order {}", event.orderId());
    }

    private String extractOrderIdBestEffort(String innerMessage) {
        try {
            return objectMapper.readTree(innerMessage).path("orderId").asText("unknown");
        } catch (Exception e) {
            return "unknown";
        }
    }
}
