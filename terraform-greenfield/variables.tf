# variables.tf
# Declares the inputs this Terraform module accepts.
# Values come from terraform.tfvars (gitignored).

variable "aws_region" {
  description = "AWS region where all resources will be created"
  type        = string
  default     = "eu-north-1"
}

variable "project_name" {
  description = "Short project identifier, used as a prefix in resource names and tags"
  type        = string
  default     = "react-s3-cloudfront-demo-greenfield"
}

variable "s3_bucket_name" {
  description = "Globally unique S3 bucket name to host the built React app"
  type        = string
  # No default -- forces the user to supply a unique name.
}

variable "iam_user_name" {
  description = "Name of the IAM user that GitHub Actions will use to deploy"
  type        = string
  default     = "github-actions-react-s3-cloudfront-greenfield"
}

variable "tags" {
  description = "Tags applied to every resource. Useful for cost tracking and ownership."
  type        = map(string)
  default = {
    Project   = "react-s3-cloudfront-demo-greenfield"
    ManagedBy = "Terraform"
    Approach  = "Greenfield"
    Owner     = "danish-khan"
  }
}
