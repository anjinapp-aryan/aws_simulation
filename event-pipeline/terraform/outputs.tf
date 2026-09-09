output "topic_arn" {
  value = aws_sns_topic.order_events.arn
}

output "queue_url" {
  value = aws_sqs_queue.processing.url
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.url
}

output "table_name" {
  value = aws_dynamodb_table.orders.name
}

output "archive_bucket" {
  value = aws_s3_bucket.archive.bucket
}
