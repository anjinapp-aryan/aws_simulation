package com.interviewprep.serverlessapi.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record CreateTaskRequest(
        @NotBlank @Size(max = 200) String title,
        @Size(max = 2000) String description
) {
}
