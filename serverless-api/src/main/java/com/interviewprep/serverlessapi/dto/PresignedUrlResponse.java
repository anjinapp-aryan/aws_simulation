package com.interviewprep.serverlessapi.dto;

public record PresignedUrlResponse(String url, String key, long expiresInSeconds) {
}
