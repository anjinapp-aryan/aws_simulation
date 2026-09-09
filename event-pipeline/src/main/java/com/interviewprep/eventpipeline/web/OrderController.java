package com.interviewprep.eventpipeline.web;

import com.interviewprep.eventpipeline.dto.CreateOrderRequest;
import com.interviewprep.eventpipeline.dto.OrderCreatedEvent;
import com.interviewprep.eventpipeline.model.OrderRecord;
import com.interviewprep.eventpipeline.publisher.OrderEventPublisher;
import com.interviewprep.eventpipeline.repository.OrderRepository;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/orders")
public class OrderController {

    private final OrderEventPublisher publisher;
    private final OrderRepository orderRepository;

    public OrderController(OrderEventPublisher publisher, OrderRepository orderRepository) {
        this.publisher = publisher;
        this.orderRepository = orderRepository;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.ACCEPTED)
    public Map<String, String> createOrder(@Valid @RequestBody CreateOrderRequest request) {
        String orderId = UUID.randomUUID().toString();
        OrderCreatedEvent event = new OrderCreatedEvent(
                orderId, request.customerId(), request.item(), request.quantity(),
                request.amount(), Instant.now().toString());

        String messageId = publisher.publish(event);
        return Map.of("orderId", orderId, "snsMessageId", messageId, "status", "ACCEPTED");
    }

    @GetMapping("/{orderId}")
    public ResponseEntity<OrderRecord> getOrder(@PathVariable String orderId) {
        return orderRepository.findById(orderId)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }
}
