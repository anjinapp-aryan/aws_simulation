package com.interviewprep.serverlessapi;

import com.interviewprep.serverlessapi.dto.CreateTaskRequest;
import com.interviewprep.serverlessapi.dto.PresignedUrlResponse;
import com.interviewprep.serverlessapi.dto.TaskResponse;
import com.interviewprep.serverlessapi.dto.UpdateTaskRequest;
import com.interviewprep.serverlessapi.model.TaskStatus;
import org.junit.jupiter.api.Assumptions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.test.context.ActiveProfiles;

import java.net.HttpURLConnection;
import java.net.URI;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Full-stack integration test against a real Ministack instance.
 * Requires `docker compose up -d ministack` and `terraform apply` (in serverless-api/terraform)
 * to have run first. Self-skips when Ministack is not reachable.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ActiveProfiles("local")
class TaskApiIT {

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
    void createReadUpdateDeleteLifecycle() {
        ResponseEntity<TaskResponse> createResponse = restTemplate.postForEntity(
                baseUrl() + "/tasks", new CreateTaskRequest("Prepare interview notes", "AWS + Spring"), TaskResponse.class);
        assertThat(createResponse.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        String id = createResponse.getBody().id();

        ResponseEntity<TaskResponse> getResponse = restTemplate.getForEntity(
                baseUrl() + "/tasks/" + id, TaskResponse.class);
        assertThat(getResponse.getBody().title()).isEqualTo("Prepare interview notes");
        assertThat(getResponse.getBody().status()).isEqualTo(TaskStatus.TODO);

        restTemplate.put(baseUrl() + "/tasks/" + id,
                new UpdateTaskRequest("Prepare interview notes", "updated desc", TaskStatus.DONE));

        ResponseEntity<TaskResponse> afterUpdate = restTemplate.getForEntity(
                baseUrl() + "/tasks/" + id, TaskResponse.class);
        assertThat(afterUpdate.getBody().status()).isEqualTo(TaskStatus.DONE);

        restTemplate.exchange(baseUrl() + "/tasks/" + id, HttpMethod.DELETE, HttpEntity.EMPTY, Void.class);

        ResponseEntity<TaskResponse> afterDelete = restTemplate.getForEntity(
                baseUrl() + "/tasks/" + id, TaskResponse.class);
        assertThat(afterDelete.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    }

    @Test
    void presignsUploadUrlForAttachment() {
        ResponseEntity<TaskResponse> createResponse = restTemplate.postForEntity(
                baseUrl() + "/tasks", new CreateTaskRequest("With attachment", null), TaskResponse.class);
        String id = createResponse.getBody().id();

        ResponseEntity<PresignedUrlResponse> presignResponse = restTemplate.postForEntity(
                baseUrl() + "/tasks/" + id + "/attachments/upload-url?fileName=resume.pdf",
                null, PresignedUrlResponse.class);

        assertThat(presignResponse.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(presignResponse.getBody().url()).contains("task-attachments-bucket");
        assertThat(presignResponse.getBody().key()).isEqualTo("tasks/" + id + "/resume.pdf");
    }
}
