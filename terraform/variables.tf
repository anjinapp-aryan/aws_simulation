variable "use_local_endpoints" {
  description = "true = target Ministack on localhost:4566; false = real AWS"
  type        = bool
  default     = true
}

variable "ministack_endpoint" {
  description = "Ministack single edge-port URL"
  type        = string
  default     = "http://localhost:4566"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "bucket_name" {
  type    = string
  default = "health-check-bucket"
}

variable "table_name" {
  type    = string
  default = "HealthCheckTable"
}

variable "queue_name" {
  type    = string
  default = "health-check-queue"
}

variable "topic_name" {
  type    = string
  default = "health-check-topic"
}

variable "stream_name" {
  type    = string
  default = "health-check-stream"
}
