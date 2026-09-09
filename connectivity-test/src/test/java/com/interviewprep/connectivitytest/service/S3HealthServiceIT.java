package com.interviewprep.connectivitytest.service;

import org.junit.jupiter.api.Assumptions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

import java.net.HttpURLConnection;
import java.net.URI;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Integration test against a real Ministack instance.
 * Requires `docker compose up -d ministack && ./init-ministack.sh` to have run first.
 * Skips itself (instead of failing the build) when Ministack is not reachable.
 */
@SpringBootTest
@ActiveProfiles("local")
class S3HealthServiceIT {

    @Autowired
    private S3HealthService s3HealthService;

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

    @Test
    void writesAndReadsObjectFromS3() {
        String result = s3HealthService.writeAndRead("it-test.txt", "integration-test-content");
        assertThat(result).isEqualTo("integration-test-content");
    }
}
