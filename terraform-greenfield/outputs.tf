# outputs.tf
# Values printed after `terraform apply`.
# Useful for plugging into GitHub Secrets, scripts, or just confirming what got created.

output "s3_bucket_name" {
  description = "Name of the S3 bucket hosting the React app"
  value       = aws_s3_bucket.website.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket (used in IAM policies)"
  value       = aws_s3_bucket.website.arn
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID -- paste this into GitHub Secrets"
  value       = aws_cloudfront_distribution.website.id
}

output "cloudfront_domain_name" {
  description = "Public URL of the deployed site (without https://)"
  value       = aws_cloudfront_distribution.website.domain_name
}

output "cloudfront_url" {
  description = "Full HTTPS URL of the deployed site"
  value       = "https://${aws_cloudfront_distribution.website.domain_name}"
}

output "iam_user_name" {
  description = "Name of the IAM user for GitHub Actions"
  value       = aws_iam_user.github_actions.name
}

output "aws_region" {
  description = "AWS region everything is deployed in"
  value       = var.aws_region
}
