package com.interviewprep.eventpipeline;

import com.interviewprep.eventpipeline.dto.CreateOrderRequest;
import org.junit.jupiter.api.Assumptions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.test.context.ActiveProfiles;

import java.net.HttpURLConnection;
import java.net.URI;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;
import static java.time.Duration.ofSeconds;

/**
 * End-to-end: POST /orders -> SNS -> SQS -> plain-SDK consumer (default mode) -> DynamoDB.
 * Requires `docker compose up -d ministack` and `terraform apply` (event-pipeline/terraform)
 * to have run first. Self-skips when Ministack is not reachable.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ActiveProfiles("local")
class OrderPipelineIT {

    @LocalServerPort
    private int port;

    @Autowired
    private TestRestTemplate restTemplate;

    @BeforeEach
    void checkMinistackIsUp() {
        boolean reachable;
        try {
            HttpURLConnection conn = (HttpURLConnection) URI.create("http://localhost:4566/_ministack/health")
                    .toURL().openConnection();
            conn.setConnectTimeout(1000);
            reachable = conn.getResponseCode() == 200;
        } catch (Exception e) {
            reachable = false;
        }
        Assumptions.assumeTrue(reachable, "Ministack not running on localhost:4566 - skipping integration test");
    }

    private String baseUrl() {
        return "http://localhost:" + port;
    }

    @Test
    @SuppressWarnings("unchecked")
    void orderFlowsThroughSnsAndSqsIntoDynamoDb() {
        ResponseEntity<Map> createResponse = restTemplate.postForEntity(
                baseUrl() + "/orders",
                new CreateOrderRequest("cust-it", "Test Widget", 3, 19.99),
                Map.class);
        assertThat(createResponse.getStatusCode()).isEqualTo(HttpStatus.ACCEPTED);
        String orderId = (String) createResponse.getBody().get("orderId");

        await().atMost(ofSeconds(15)).pollInterval(ofSeconds(1)).untilAsserted(() -> {
            ResponseEntity<Map> getResponse = restTemplate.getForEntity(baseUrl() + "/orders/" + orderId, Map.class);
            assertThat(getResponse.getStatusCode()).isEqualTo(HttpStatus.OK);
            assertThat(getResponse.getBody().get("status")).isEqualTo("PROCESSED");
        });
    }
}
