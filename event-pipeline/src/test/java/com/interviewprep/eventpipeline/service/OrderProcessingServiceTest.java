package com.interviewprep.eventpipeline.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.interviewprep.eventpipeline.model.OrderRecord;
import com.interviewprep.eventpipeline.repository.OrderRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

class OrderProcessingServiceTest {

    private OrderRepository orderRepository;
    private EventArchiveService archiveService;
    private OrderProcessingService service;

    @BeforeEach
    void setUp() {
        orderRepository = mock(OrderRepository.class);
        archiveService = mock(EventArchiveService.class);
        service = new OrderProcessingService(new ObjectMapper(), orderRepository, archiveService);
    }

    private String snsEnvelope(String innerJson) {
        return """
                {"Type":"Notification","MessageId":"m1","TopicArn":"arn:aws:sns:...","Message":%s}
                """.formatted(new ObjectMapper().valueToTree(innerJson).toString());
    }

    @Test
    void processesValidEventAndSavesToRepository() throws Exception {
        String inner = """
                {"orderId":"o1","customerId":"c1","item":"Keyboard","quantity":2,"amount":50.0,"createdAt":"2026-01-01T00:00:00Z"}
                """;
        service.process(snsEnvelope(inner));

        ArgumentCaptor<OrderRecord> captor = ArgumentCaptor.forClass(OrderRecord.class);
        verify(orderRepository).save(captor.capture());
        assertThat(captor.getValue().getOrderId()).isEqualTo("o1");
        assertThat(captor.getValue().getStatus()).isEqualTo("PROCESSED");
        verify(archiveService).archive(eq("o1"), anyString());
    }

    @Test
    void rejectsEventWithZeroQuantityAndDoesNotSave() {
        String inner = """
                {"orderId":"o2","customerId":"c1","item":"Ghost","quantity":0,"amount":0.0,"createdAt":"2026-01-01T00:00:00Z"}
                """;

        assertThatThrownBy(() -> service.process(snsEnvelope(inner)))
                .isInstanceOf(IllegalArgumentException.class);

        verify(orderRepository, never()).save(any());
        // Archived even though processing failed - raw event preserved for replay/audit.
        verify(archiveService).archive(eq("o2"), anyString());
    }
}
