variable "create" {
  description = "Whether to create this resource or not?"
  type        = bool
  default     = true
}

variable "region" {
    description = "The region to create the S3 bucket in"
    type        = string
}

variable "bucket_name" {
    description = "The name of the S3 bucket"
    type        = string
}

variable "bucket_prefix" {
    description = "The prefix of the S3 bucket"
    type        = string
    default     = "app-"
}

variable "force_destroy" {
    description = "Whether to force destroy the S3 bucket"
    type        = bool
    default     = true
}