package com.interviewprep.serverlessapi.dto;

import com.interviewprep.serverlessapi.model.Task;
import com.interviewprep.serverlessapi.model.TaskStatus;

public record TaskResponse(
        String id,
        String title,
        String description,
        TaskStatus status,
        String createdAt,
        String updatedAt,
        String attachmentKey
) {
    public static TaskResponse from(Task task) {
        return new TaskResponse(
                task.getId(),
                task.getTitle(),
                task.getDescription(),
                task.getStatus(),
                task.getCreatedAt(),
                task.getUpdatedAt(),
                task.getAttachmentKey());
    }
}
