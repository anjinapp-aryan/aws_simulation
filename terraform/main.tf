resource "aws_s3_bucket" "health_check" {
  bucket = var.bucket_name
}

resource "aws_dynamodb_table" "health_check" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_sqs_queue" "health_check" {
  name = var.queue_name
}

resource "aws_sns_topic" "health_check" {
  name = var.topic_name
}

resource "aws_sns_topic_subscription" "health_check_sqs" {
  topic_arn = aws_sns_topic.health_check.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.health_check.arn
}

resource "aws_sqs_queue_policy" "allow_sns" {
  queue_url = aws_sqs_queue.health_check.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.health_check.arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = aws_sns_topic.health_check.arn }
      }
    }]
  })
}

resource "aws_kinesis_stream" "health_check" {
  name             = var.stream_name
  shard_count      = 1
  retention_period = 24
}
