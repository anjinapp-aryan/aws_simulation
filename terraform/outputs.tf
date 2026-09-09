output "bucket_name" {
  value = aws_s3_bucket.health_check.bucket
}

output "table_name" {
  value = aws_dynamodb_table.health_check.name
}

output "queue_url" {
  value = aws_sqs_queue.health_check.url
}

output "topic_arn" {
  value = aws_sns_topic.health_check.arn
}

output "stream_name" {
  value = aws_kinesis_stream.health_check.name
}
