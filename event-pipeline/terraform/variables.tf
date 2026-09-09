variable "use_local_endpoints" {
  type    = bool
  default = true
}

variable "ministack_endpoint" {
  type    = string
  default = "http://localhost:4566"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "topic_name" {
  type    = string
  default = "order-events-topic"
}

variable "queue_name" {
  type    = string
  default = "order-processing-queue"
}

variable "dlq_name" {
  type    = string
  default = "order-processing-dlq"
}

variable "table_name" {
  type    = string
  default = "OrdersTable"
}

variable "archive_bucket_name" {
  type    = string
  default = "order-events-archive"
}

variable "max_receive_count" {
  description = "Deliveries attempted before a message is routed to the DLQ"
  type        = number
  default     = 3
}
