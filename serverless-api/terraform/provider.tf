provider "aws" {
  region                      = var.region
  access_key                  = var.use_local_endpoints ? "test" : null
  secret_key                  = var.use_local_endpoints ? "test" : null
  skip_credentials_validation = var.use_local_endpoints
  skip_metadata_api_check     = var.use_local_endpoints
  skip_requesting_account_id  = var.use_local_endpoints
  s3_use_path_style           = var.use_local_endpoints

  endpoints {
    s3       = var.use_local_endpoints ? var.ministack_endpoint : null
    dynamodb = var.use_local_endpoints ? var.ministack_endpoint : null
    iam      = var.use_local_endpoints ? var.ministack_endpoint : null
    sts      = var.use_local_endpoints ? var.ministack_endpoint : null
  }
}
