package com.interviewprep.eventpipeline.repository;

import com.interviewprep.eventpipeline.config.AwsProperties;
import com.interviewprep.eventpipeline.model.OrderRecord;
import org.springframework.stereotype.Repository;
import software.amazon.awssdk.enhanced.dynamodb.DynamoDbEnhancedClient;
import software.amazon.awssdk.enhanced.dynamodb.DynamoDbTable;
import software.amazon.awssdk.enhanced.dynamodb.Key;
import software.amazon.awssdk.enhanced.dynamodb.TableSchema;

import java.util.Optional;

@Repository
public class OrderRepository {

    private final DynamoDbTable<OrderRecord> table;

    public OrderRepository(DynamoDbEnhancedClient enhancedClient, AwsProperties props) {
        this.table = enhancedClient.table(props.resources().table(), TableSchema.fromBean(OrderRecord.class));
    }

    public void save(OrderRecord order) {
        table.putItem(order);
    }

    public Optional<OrderRecord> findById(String orderId) {
        return Optional.ofNullable(table.getItem(Key.builder().partitionValue(orderId).build()));
    }
}
