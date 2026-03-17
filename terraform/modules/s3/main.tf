resource "aws_s3_bucket" "this" {

  count = var.create ? 1 : 0
  bucket_prefix = var.bucket_prefix
  bucket = var.bucket_name
  region = var.region

  force_destroy = var.force_destroy
}