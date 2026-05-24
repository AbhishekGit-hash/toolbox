
output "s3_bucket_object_id" {
    description = "The ID of the S3 bucket object"
    value = module.test_s3_bucket.s3_object_id
}

output "s3_bucket_object_arn" {
    description = "The ARN of the S3 bucket object"
    value = module.test_s3_bucket.s3_object_arn
}