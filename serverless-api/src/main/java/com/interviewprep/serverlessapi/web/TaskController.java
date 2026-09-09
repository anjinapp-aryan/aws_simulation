package com.interviewprep.serverlessapi.web;

import com.interviewprep.serverlessapi.dto.CreateTaskRequest;
import com.interviewprep.serverlessapi.dto.PresignedUrlResponse;
import com.interviewprep.serverlessapi.dto.TaskResponse;
import com.interviewprep.serverlessapi.dto.UpdateTaskRequest;
import com.interviewprep.serverlessapi.service.AttachmentService;
import com.interviewprep.serverlessapi.service.TaskService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/tasks")
public class TaskController {

    private final TaskService taskService;
    private final AttachmentService attachmentService;

    public TaskController(TaskService taskService, AttachmentService attachmentService) {
        this.taskService = taskService;
        this.attachmentService = attachmentService;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public TaskResponse create(@Valid @RequestBody CreateTaskRequest request) {
        return TaskResponse.from(taskService.create(request));
    }

    @GetMapping("/{id}")
    public TaskResponse get(@PathVariable String id) {
        return TaskResponse.from(taskService.get(id));
    }

    @GetMapping
    public List<TaskResponse> list() {
        return taskService.list().stream().map(TaskResponse::from).toList();
    }

    @PutMapping("/{id}")
    public TaskResponse update(@PathVariable String id, @Valid @RequestBody UpdateTaskRequest request) {
        return TaskResponse.from(taskService.update(id, request));
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable String id) {
        taskService.delete(id);
    }

    @PostMapping("/{id}/attachments/upload-url")
    public PresignedUrlResponse presignUpload(@PathVariable String id, @RequestParam String fileName) {
        return attachmentService.presignUpload(id, fileName);
    }

    @PostMapping("/{id}/attachments/confirm")
    public TaskResponse confirmAttachment(@PathVariable String id, @RequestParam String key) {
        return TaskResponse.from(taskService.attachFile(id, key));
    }

    @GetMapping("/{id}/attachments/download-url")
    public PresignedUrlResponse presignDownload(@PathVariable String id) {
        String key = taskService.get(id).getAttachmentKey();
        return attachmentService.presignDownload(key);
    }
}
