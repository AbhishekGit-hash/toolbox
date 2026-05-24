terraform {
    required_version = ">= 1.0.0"
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "~> 3.0"
        }
    }
}



module "test_s3_bucket" {
    source = "./modules/s3"

    bucket_name = "test-s3-bucket"
    force_destroy_s3_bucket = true
}