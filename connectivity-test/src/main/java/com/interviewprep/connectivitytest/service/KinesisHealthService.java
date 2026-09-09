package com.interviewprep.connectivitytest.service;

import com.interviewprep.connectivitytest.config.AwsProperties;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.kinesis.KinesisClient;
import software.amazon.awssdk.services.kinesis.model.*;

import java.nio.charset.StandardCharsets;
import java.util.List;

@Service
public class KinesisHealthService {

    private final KinesisClient kinesisClient;
    private final String streamName;

    public KinesisHealthService(KinesisClient kinesisClient, AwsProperties props) {
        this.kinesisClient = kinesisClient;
        this.streamName = props.resources().stream();
    }

    public String putRecord(String partitionKey, String data) {
        var response = kinesisClient.putRecord(PutRecordRequest.builder()
                .streamName(streamName)
                .partitionKey(partitionKey)
                .data(SdkBytes.fromUtf8String(data))
                .build());
        return response.sequenceNumber();
    }

    public List<String> readLatestRecords() {
        String shardId = kinesisClient.describeStream(DescribeStreamRequest.builder()
                        .streamName(streamName).build())
                .streamDescription().shards().get(0).shardId();

        String shardIterator = kinesisClient.getShardIterator(GetShardIteratorRequest.builder()
                        .streamName(streamName)
                        .shardId(shardId)
                        .shardIteratorType(ShardIteratorType.TRIM_HORIZON)
                        .build())
                .shardIterator();

        GetRecordsResponse records = kinesisClient.getRecords(GetRecordsRequest.builder()
                .shardIterator(shardIterator)
                .limit(10)
                .build());

        return records.records().stream()
                .map(r -> r.data().asString(StandardCharsets.UTF_8))
                .toList();
    }
}
