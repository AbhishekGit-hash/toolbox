# variable "aws_access_key_id" {
#     description = "The access key id for the aws account"
#     type = string
# }

# variable "aws_access_secret_key" {
#     description = "The access secret key for the aws account"
#     type = string
# }

# variable "aws_session_token" {
#     description = "The session token for the aws account"
#     type = string
# }

# variable "aws_sts_region" {
#     description = "The region to deploy the resources"
#     type = string
#     default = "us-east-1"
# }

# # Provided by engineer
# variable "aws_account_id" {
#     description = "The account id for the aws account"
#     type = string
# }

variable "aws_region" {
    description = "The region to deploy the resources"
    type = string
    default = "us-east-1"
}
