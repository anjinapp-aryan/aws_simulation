resource "aws_dynamodb_table" "tasks" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_s3_bucket" "attachments" {
  bucket = var.attachments_bucket_name
}

# Browsers upload directly to S3 via presigned PUT URLs (see AttachmentService) — needs CORS.
resource "aws_s3_bucket_cors_configuration" "attachments" {
  bucket = aws_s3_bucket.attachments.id

  cors_rule {
    allowed_methods = ["PUT", "GET"]
    allowed_origins = ["*"]
    allowed_headers = ["*"]
    max_age_seconds = 3000
  }
}
