# variables.tf
# Declares all the input values our Terraform code accepts.
# Think of these like function parameters: the SAME .tf code can be re-used
# with different bucket names, regions, etc. just by changing these inputs.
#
# Actual values are NOT in this file -- they go in terraform.tfvars (gitignored)
# so each engineer (or environment) can have their own values.

variable "aws_region" {
  description = "AWS region where all resources will be created"
  type        = string
  default     = "eu-north-1"
}

variable "project_name" {
  description = "Short project identifier, used as a prefix in resource names and tags"
  type        = string
  default     = "react-s3-cloudfront-demo"
}

variable "s3_bucket_name" {
  description = "Globally unique S3 bucket name to host the built React app"
  type        = string
  # No default -- this MUST be set in terraform.tfvars because bucket names are
  # global across all AWS accounts. Forcing the user to set it prevents collisions.
}

variable "iam_user_name" {
  description = "Name of the IAM user that GitHub Actions will use to deploy"
  type        = string
  default     = "github-actions-react-s3-cloudfront"
}

variable "tags" {
  description = "Tags applied to every resource. Useful for cost tracking and ownership."
  type        = map(string)
  default = {
    Project   = "react-s3-cloudfront-demo"
    ManagedBy = "Terraform"
    Owner     = "danish-khan"
  }
}
