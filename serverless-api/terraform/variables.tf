variable "use_local_endpoints" {
  description = "true = target Ministack on localhost:4566; false = real AWS"
  type        = bool
  default     = true
}

variable "ministack_endpoint" {
  type    = string
  default = "http://localhost:4566"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "table_name" {
  type    = string
  default = "TasksTable"
}

variable "attachments_bucket_name" {
  type    = string
  default = "task-attachments-bucket"
}
