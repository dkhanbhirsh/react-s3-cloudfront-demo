# main.tf
# Declares all AWS resources for the greenfield React + S3 + CloudFront setup.
# Built from scratch (no `terraform import`) so the state file fully matches reality
# from day 1. Remote state is configured in versions.tf.

# -----------------------------------------------------------------------------
# Data sources -- read-only lookups
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# S3 bucket -- stores the built React app
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "website" {
  bucket = var.s3_bucket_name
  tags   = var.tags
}

# Block all public access. Users reach the site through CloudFront only.
resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# CloudFront Origin Access Control (OAC)
# Modern AWS-recommended way to let CloudFront read a private S3 bucket.
# -----------------------------------------------------------------------------

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
  comment             = "${var.project_name} -- managed by Terraform (greenfield)"

  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id                = "s3-${var.s3_bucket_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.website.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-${var.s3_bucket_name}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # AWS managed "CachingOptimized" policy -- good defaults for static sites.
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  # PriceClass_100 -- North America + Europe only. Cheaper for a demo.
  price_class = "PriceClass_100"

  tags = var.tags
}

# -----------------------------------------------------------------------------
# S3 bucket policy -- allows ONLY this CloudFront distribution to read objects
# -----------------------------------------------------------------------------

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
