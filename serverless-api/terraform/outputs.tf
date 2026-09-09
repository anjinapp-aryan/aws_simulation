output "table_name" {
  value = aws_dynamodb_table.tasks.name
}

output "attachments_bucket" {
  value = aws_s3_bucket.attachments.bucket
}
