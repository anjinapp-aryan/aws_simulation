package com.interviewprep.serverlessapi.service;

import com.interviewprep.serverlessapi.dto.CreateTaskRequest;
import com.interviewprep.serverlessapi.dto.UpdateTaskRequest;
import com.interviewprep.serverlessapi.exception.TaskNotFoundException;
import com.interviewprep.serverlessapi.model.Task;
import com.interviewprep.serverlessapi.model.TaskStatus;
import com.interviewprep.serverlessapi.repository.TaskRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class TaskServiceTest {

    private TaskRepository taskRepository;
    private TaskService taskService;

    @BeforeEach
    void setUp() {
        taskRepository = mock(TaskRepository.class);
        taskService = new TaskService(taskRepository);
    }

    @Test
    void createsTaskWithGeneratedIdAndTodoStatus() {
        when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

        Task created = taskService.create(new CreateTaskRequest("Write report", "Q3 summary"));

        assertThat(created.getId()).isNotBlank();
        assertThat(created.getStatus()).isEqualTo(TaskStatus.TODO);
        assertThat(created.getTitle()).isEqualTo("Write report");
        verify(taskRepository).save(any(Task.class));
    }

    @Test
    void getThrowsWhenTaskMissing() {
        when(taskRepository.findById("missing")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> taskService.get("missing"))
                .isInstanceOf(TaskNotFoundException.class);
    }

    @Test
    void updateAppliesNewFieldsAndTimestamp() {
        Task existing = new Task();
        existing.setId("t1");
        existing.setTitle("old");
        existing.setStatus(TaskStatus.TODO);
        when(taskRepository.findById("t1")).thenReturn(Optional.of(existing));
        when(taskRepository.update(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

        Task updated = taskService.update("t1", new UpdateTaskRequest("new title", "desc", TaskStatus.IN_PROGRESS));

        ArgumentCaptor<Task> captor = ArgumentCaptor.forClass(Task.class);
        verify(taskRepository).update(captor.capture());
        assertThat(captor.getValue().getTitle()).isEqualTo("new title");
        assertThat(captor.getValue().getStatus()).isEqualTo(TaskStatus.IN_PROGRESS);
        assertThat(updated.getUpdatedAt()).isNotBlank();
    }

    @Test
    void deleteThrowsWhenTaskMissing() {
        when(taskRepository.findById("missing")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> taskService.delete("missing"))
                .isInstanceOf(TaskNotFoundException.class);
        verify(taskRepository, never()).deleteById(any());
    }
}
