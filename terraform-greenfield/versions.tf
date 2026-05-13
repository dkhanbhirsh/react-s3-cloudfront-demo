# versions.tf
# Pins Terraform and AWS provider versions, and configures REMOTE STATE.
#
# REMOTE STATE configuration:
#   - state file lives in S3 (versioned, encrypted, private)
#   - state lock uses S3's built-in conditional writes (use_lockfile)
#
# The S3 bucket is NOT managed by this Terraform.
# It was bootstrapped manually with AWS CLI -- chicken-and-egg.
# Bootstrap commands are documented in README.md for reproducibility.
#
# Note on locking:
#   Older Terraform setups used a separate DynamoDB table (dynamodb_table param).
#   That parameter is deprecated as of Terraform 1.10+. The newer use_lockfile
#   approach stores the lock as a small file inside the same S3 bucket -- simpler,
#   one fewer resource to maintain, same correctness guarantee.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "danish-terraform-state"
    key          = "react-s3-cloudfront-demo-greenfield/terraform.tfstate"
    region       = "eu-north-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.aws_region
}
