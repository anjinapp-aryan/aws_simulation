provider "aws" {
  region                      = var.region
  access_key                  = var.use_local_endpoints ? "test" : null
  secret_key                  = var.use_local_endpoints ? "test" : null
  skip_credentials_validation = var.use_local_endpoints
  skip_metadata_api_check     = var.use_local_endpoints
  skip_requesting_account_id  = var.use_local_endpoints
  s3_use_path_style           = var.use_local_endpoints

  # Endpoint URLs resolve to null (real AWS regional endpoints) when use_local_endpoints = false.
  endpoints {
    s3       = var.use_local_endpoints ? var.ministack_endpoint : null
    dynamodb = var.use_local_endpoints ? var.ministack_endpoint : null
    sqs      = var.use_local_endpoints ? var.ministack_endpoint : null
    sns      = var.use_local_endpoints ? var.ministack_endpoint : null
    kinesis  = var.use_local_endpoints ? var.ministack_endpoint : null
    iam      = var.use_local_endpoints ? var.ministack_endpoint : null
    sts      = var.use_local_endpoints ? var.ministack_endpoint : null
  }
}
