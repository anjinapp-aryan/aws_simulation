package com.interviewprep.serverlessapi.service;

import com.interviewprep.serverlessapi.dto.CreateTaskRequest;
import com.interviewprep.serverlessapi.dto.UpdateTaskRequest;
import com.interviewprep.serverlessapi.exception.TaskNotFoundException;
import com.interviewprep.serverlessapi.model.Task;
import com.interviewprep.serverlessapi.model.TaskStatus;
import com.interviewprep.serverlessapi.repository.TaskRepository;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

@Service
public class TaskService {

    private final TaskRepository taskRepository;

    public TaskService(TaskRepository taskRepository) {
        this.taskRepository = taskRepository;
    }

    public Task create(CreateTaskRequest request) {
        Task task = new Task();
        task.setId(UUID.randomUUID().toString());
        task.setTitle(request.title());
        task.setDescription(request.description());
        task.setStatus(TaskStatus.TODO);
        String now = Instant.now().toString();
        task.setCreatedAt(now);
        task.setUpdatedAt(now);
        return taskRepository.save(task);
    }

    public Task get(String id) {
        return taskRepository.findById(id).orElseThrow(() -> new TaskNotFoundException(id));
    }

    public List<Task> list() {
        return taskRepository.findAll();
    }

    public Task update(String id, UpdateTaskRequest request) {
        Task existing = get(id);
        existing.setTitle(request.title());
        existing.setDescription(request.description());
        existing.setStatus(request.status());
        existing.setUpdatedAt(Instant.now().toString());
        return taskRepository.update(existing);
    }

    public void delete(String id) {
        get(id);
        taskRepository.deleteById(id);
    }

    public Task attachFile(String id, String attachmentKey) {
        Task existing = get(id);
        existing.setAttachmentKey(attachmentKey);
        existing.setUpdatedAt(Instant.now().toString());
        return taskRepository.update(existing);
    }
}
