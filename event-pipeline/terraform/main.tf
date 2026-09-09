resource "aws_sqs_queue" "dlq" {
  name = var.dlq_name
}

resource "aws_sqs_queue" "processing" {
  name = var.queue_name

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount      = var.max_receive_count
  })
}

resource "aws_sns_topic" "order_events" {
  name = var.topic_name
}

resource "aws_sns_topic_subscription" "processing_queue" {
  topic_arn = aws_sns_topic.order_events.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.processing.arn
}

resource "aws_sqs_queue_policy" "allow_sns" {
  queue_url = aws_sqs_queue.processing.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.processing.arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = aws_sns_topic.order_events.arn }
      }
    }]
  })
}

resource "aws_dynamodb_table" "orders" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "orderId"

  attribute {
    name = "orderId"
    type = "S"
  }
}

resource "aws_s3_bucket" "archive" {
  bucket = var.archive_bucket_name
}
