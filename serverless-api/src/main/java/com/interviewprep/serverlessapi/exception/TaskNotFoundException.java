package com.interviewprep.serverlessapi.exception;

public class TaskNotFoundException extends RuntimeException {
    public TaskNotFoundException(String id) {
        super("Task not found: " + id);
    }
}
