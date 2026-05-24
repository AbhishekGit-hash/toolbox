


provider "aws" {
    # access_key = var.aws_access_key_id
    # secret_key = var.aws_access_secret_key
    # token = var.aws_session_token
    region = var.aws_region
    # sts_region = var.aws_sts_region
    # assume_role {
    #   role_arn = "arn:aws:iam::${var.aws_account_id}:role/tfe-module-pave-role"
    # }
}
