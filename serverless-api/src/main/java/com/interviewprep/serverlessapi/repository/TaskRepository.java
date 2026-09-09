package com.interviewprep.serverlessapi.repository;

import com.interviewprep.serverlessapi.config.AwsProperties;
import com.interviewprep.serverlessapi.model.Task;
import org.springframework.stereotype.Repository;
import software.amazon.awssdk.enhanced.dynamodb.DynamoDbEnhancedClient;
import software.amazon.awssdk.enhanced.dynamodb.DynamoDbTable;
import software.amazon.awssdk.enhanced.dynamodb.Key;
import software.amazon.awssdk.enhanced.dynamodb.TableSchema;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

@Repository
public class TaskRepository {

    private final DynamoDbTable<Task> table;

    public TaskRepository(DynamoDbEnhancedClient enhancedClient, AwsProperties props) {
        this.table = enhancedClient.table(props.resources().table(), TableSchema.fromBean(Task.class));
    }

    public Task save(Task task) {
        table.putItem(task);
        return task;
    }

    public Optional<Task> findById(String id) {
        return Optional.ofNullable(table.getItem(Key.builder().partitionValue(id).build()));
    }

    public List<Task> findAll() {
        List<Task> tasks = new ArrayList<>();
        table.scan().items().forEach(tasks::add);
        return tasks;
    }

    public Task update(Task task) {
        return table.updateItem(task);
    }

    public void deleteById(String id) {
        table.deleteItem(Key.builder().partitionValue(id).build());
    }
}
