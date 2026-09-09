package com.interviewprep.eventpipeline.dto;

/** The event payload published to SNS and consumed off SQS. */
public record OrderCreatedEvent(
        String orderId,
        String customerId,
        String item,
        int quantity,
        double amount,
        String createdAt
) {
}
