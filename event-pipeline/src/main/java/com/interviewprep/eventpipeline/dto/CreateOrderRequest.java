package com.interviewprep.eventpipeline.dto;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Positive;

public record CreateOrderRequest(
        @NotBlank String customerId,
        @NotBlank String item,
        @Min(1) int quantity,
        @Positive double amount
) {
}
