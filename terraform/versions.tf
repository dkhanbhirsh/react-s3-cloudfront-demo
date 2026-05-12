# versions.tf
# Tells Terraform which version of itself and the AWS provider to use.
# Pinning versions makes builds reproducible -- the same code today and 6 months
# from now produces the same result.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# The AWS provider tells Terraform how to talk to AWS.
# Region is read from a variable (defined in variables.tf) so it's easy to change.
provider "aws" {
  region = var.aws_region
}
