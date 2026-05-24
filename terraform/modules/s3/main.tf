resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "this" {

  count = var.create ? 1 : 0
  bucket        = var.bucket_name != null && var.bucket_name != "" ? "${var.bucket_name}-${random_id.bucket_suffix.hex}" : null
  force_destroy = var.force_destroy_s3_bucket
  
}