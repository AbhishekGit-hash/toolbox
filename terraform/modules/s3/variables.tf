variable "create" {
  description = "Whether to create this resource or not?"
  type        = bool
  default     = true
}

variable "bucket_name" {
    description = "The name of the S3 bucket"
    type        = string
}

variable "force_destroy_s3_bucket" {
    description = "Whether to force destroy the S3 bucket"
    type        = bool
    default     = true
}