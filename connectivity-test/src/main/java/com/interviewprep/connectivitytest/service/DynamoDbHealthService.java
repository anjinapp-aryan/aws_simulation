package com.interviewprep.connectivitytest.service;

import com.interviewprep.connectivitytest.config.AwsProperties;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.GetItemRequest;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;

import java.util.Map;

@Service
public class DynamoDbHealthService {

    private final DynamoDbClient dynamoDbClient;
    private final String table;

    public DynamoDbHealthService(DynamoDbClient dynamoDbClient, AwsProperties props) {
        this.dynamoDbClient = dynamoDbClient;
        this.table = props.resources().table();
    }

    public Map<String, String> writeAndRead(String id, String message) {
        dynamoDbClient.putItem(PutItemRequest.builder()
                .tableName(table)
                .item(Map.of(
                        "id", AttributeValue.fromS(id),
                        "message", AttributeValue.fromS(message)))
                .build());

        var response = dynamoDbClient.getItem(GetItemRequest.builder()
                .tableName(table)
                .key(Map.of("id", AttributeValue.fromS(id)))
                .build());

        return Map.of(
                "id", response.item().get("id").s(),
                "message", response.item().get("message").s());
    }
}
