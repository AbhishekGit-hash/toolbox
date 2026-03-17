output "s3_object_id" {
  description = "The key of S3 object"
  value       = try(aws_s3_object.this[0].id, "")
}

output "s3_object_arn" {
  description = "The ARN of the S3 object"
  value       = try(aws_s3_object.this[0].arn, "")
}