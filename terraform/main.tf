# main.tf
# Declares all AWS resources Terraform will manage:
#   - S3 bucket (private)
#   - CloudFront distribution
#   - CloudFront Origin Access Control (OAC) -- the secure bridge between
#     CloudFront and the private S3 bucket
#   - S3 bucket policy granting CloudFront read access
#   - IAM user that GitHub Actions uses to deploy
#   - IAM policy attached to that user (least-privilege)

# -----------------------------------------------------------------------------
# Data sources -- read-only lookups, not resources we create
# -----------------------------------------------------------------------------

# Look up the current AWS account ID. We need it for the IAM policy ARN.
# Using a data source means the policy stays correct even if the code runs
# in a different AWS account.
data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# S3 bucket -- stores the built React app
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "website" {
  bucket = var.s3_bucket_name
  tags   = var.tags
}

# Block ALL public access to the bucket. Users will reach the site through
# CloudFront, never directly. This is the secure default.
resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# CloudFront Origin Access Control (OAC)
# -----------------------------------------------------------------------------
# OAC is how CloudFront authenticates itself to a private S3 bucket.
# Without it, you'd have to make the bucket public (insecure) or use the
# older OAI mechanism (deprecated). OAC is the modern, AWS-recommended pattern.

resource "aws_cloudfront_origin_access_control" "website" {
  name                              = "${var.project_name}-oac"
  description                       = "OAC for ${var.project_name} S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# -----------------------------------------------------------------------------
# CloudFront distribution -- the global CDN that serves the site
# -----------------------------------------------------------------------------

resource "aws_cloudfront_distribution" "website" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "React demo app -- managed by Terraform"

  # Origin = where CloudFront fetches content from = our S3 bucket
  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id                = "s3-${var.s3_bucket_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.website.id
  }

  # Default cache behavior: cache aggressively, force HTTPS
  default_cache_behavior {
    target_origin_id       = "s3-${var.s3_bucket_name}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # CachingOptimized -- AWS managed cache policy, good defaults for static sites
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  # No geo restrictions -- serve worldwide
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Use the default *.cloudfront.net certificate (free HTTPS, no custom domain)
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  # Cheaper price class for a demo -- North America + Europe only
  # Change to PriceClass_All for global edge coverage.
  price_class = "PriceClass_100"

  tags = var.tags
}

# -----------------------------------------------------------------------------
# S3 bucket policy -- allows ONLY this CloudFront distribution to read objects
# -----------------------------------------------------------------------------
# The policy uses a "Condition" that checks the request comes from our specific
# CloudFront distribution. Even another CloudFront distribution in our account
# would be denied.

resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipalReadOnly"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.website.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.website.arn
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# IAM user for GitHub Actions
# -----------------------------------------------------------------------------

resource "aws_iam_user" "github_actions" {
  name = var.iam_user_name
  tags = var.tags
}

# Inline policy attached to the GitHub Actions user.
# Permissions are scoped to ONLY our bucket and ONLY our CloudFront distribution.
# If these credentials leak, the blast radius is limited to this one demo.
resource "aws_iam_user_policy" "github_actions_deploy" {
  name = "GitHubActionsDeployPolicy"
  user = aws_iam_user.github_actions.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3DeployUploads"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.website.arn,
          "${aws_s3_bucket.website.arn}/*"
        ]
      },
      {
        Sid      = "AllowCloudFrontInvalidation"
        Effect   = "Allow"
        Action   = "cloudfront:CreateInvalidation"
        Resource = aws_cloudfront_distribution.website.arn
      }
    ]
  })
}
