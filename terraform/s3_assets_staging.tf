# Staging S3 bucket and CloudFront distribution for object storage.
# PostgreSQL, Redis, and Temporal all run in-cluster.

locals {
  staging_assets_bucket_name          = "palad-assets-staging"
  staging_assets_bucket_arn           = "arn:aws:s3:::${local.staging_assets_bucket_name}"
  staging_assets_bucket_obj_arn       = "${local.staging_assets_bucket_arn}/*"
  staging_assets_cloudfront_domain    = "static.staging.palad.ai"
  staging_assets_cloudfront_origin_id = "palad-static-assets-staging-origin"
}

resource "aws_s3_bucket" "assets_staging" {
  bucket        = local.staging_assets_bucket_name
  force_destroy = true

  tags = merge(local.eks_common_tags, {
    Name        = local.staging_assets_bucket_name
    Stack       = "assets"
    Environment = "staging"
  })
}

resource "aws_s3_bucket_public_access_block" "assets_staging" {
  bucket = aws_s3_bucket.assets_staging.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "assets_staging" {
  bucket = aws_s3_bucket.assets_staging.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets_staging" {
  bucket = aws_s3_bucket.assets_staging.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "assets_staging" {
  bucket = aws_s3_bucket.assets_staging.id

  versioning_configuration {
    status = "Suspended"
  }
}

resource "aws_s3_bucket_cors_configuration" "assets_staging" {
  bucket = aws_s3_bucket.assets_staging.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "POST", "PUT", "DELETE", "HEAD"]
    allowed_origins = ["https://staging.palad.ai"]
    expose_headers  = ["ETag", "Location"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "assets_staging" {
  bucket = aws_s3_bucket.assets_staging.id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "assets_staging_bucket_require_tls" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    actions = [
      "s3:*"
    ]
    resources = [
      local.staging_assets_bucket_arn,
      local.staging_assets_bucket_obj_arn
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "assets_staging_require_tls" {
  bucket = aws_s3_bucket.assets_staging.id
  policy = data.aws_iam_policy_document.assets_staging_bucket_require_tls.json
}

# IRSA role for palad-staging workloads to access the staging S3 bucket.
data "aws_iam_policy_document" "eks_assets_staging_irsa_assume_role" {
  count = var.create_eks_cluster ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {
      type = "Federated"
      identifiers = [
        aws_iam_openid_connect_provider.eks[0].arn
      ]
    }

    condition {
      test = "StringEquals"
      values = [
        "sts.amazonaws.com"
      ]
      variable = "${replace(aws_eks_cluster.main[0].identity[0].oidc[0].issuer, "https://", "")}:aud"
    }

    condition {
      test = "StringLike"
      values = [
        "system:serviceaccount:palad-staging:palad-web",
        "system:serviceaccount:palad-staging:palad-worker",
      ]
      variable = "${replace(aws_eks_cluster.main[0].identity[0].oidc[0].issuer, "https://", "")}:sub"
    }
  }
}

resource "aws_iam_role" "eks_assets_staging" {
  count = var.create_eks_cluster ? 1 : 0

  name               = "${var.eks_cluster_name}-assets-staging-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assets_staging_irsa_assume_role[0].json

  tags = merge(local.eks_common_tags, {
    Name        = "${var.eks_cluster_name}-assets-staging-role"
    Environment = "staging"
  })
}

data "aws_iam_policy_document" "eks_assets_staging_s3" {
  count = var.create_eks_cluster ? 1 : 0

  statement {
    sid    = "AllowBucketReadMetadata"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads"
    ]
    resources = [
      local.staging_assets_bucket_arn
    ]
  }

  statement {
    sid    = "AllowObjectReadWriteDelete"
    effect = "Allow"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:ListMultipartUploadParts",
      "s3:PutObject"
    ]
    resources = [
      local.staging_assets_bucket_obj_arn
    ]
  }
}

resource "aws_iam_policy" "eks_assets_staging_s3" {
  count = var.create_eks_cluster ? 1 : 0

  name   = "${var.eks_cluster_name}-assets-staging-s3-policy"
  policy = data.aws_iam_policy_document.eks_assets_staging_s3[0].json

  tags = merge(local.eks_common_tags, {
    Name        = "${var.eks_cluster_name}-assets-staging-s3-policy"
    Environment = "staging"
  })
}

resource "aws_iam_role_policy_attachment" "eks_assets_staging_s3" {
  count = var.create_eks_cluster ? 1 : 0

  role       = aws_iam_role.eks_assets_staging[0].name
  policy_arn = aws_iam_policy.eks_assets_staging_s3[0].arn
}

output "staging_assets_bucket_name" {
  description = "Name of the S3 bucket used by staging asset uploads"
  value       = aws_s3_bucket.assets_staging.id
}

output "staging_assets_bucket_arn" {
  description = "ARN of the S3 bucket used by staging asset uploads"
  value       = local.staging_assets_bucket_arn
}

output "eks_assets_staging_irsa_role_arn" {
  description = "IAM role ARN for IRSA access to the staging assets S3 bucket"
  value       = try(aws_iam_role.eks_assets_staging[0].arn, null)
}

# CloudFront distribution for staging assets.
# Mirrors the production setup (cloudfront_static_assets.tf) using a staging-specific domain.

data "aws_cloudfront_cache_policy" "managed_caching_optimized_staging" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "managed_caching_disabled_staging" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_response_headers_policy" "managed_simple_cors_staging" {
  name = "Managed-SimpleCORS"
}

resource "aws_acm_certificate" "static_assets_staging" {
  provider = aws.us_east_1

  domain_name       = local.staging_assets_cloudfront_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.eks_common_tags, {
    Name        = "${local.staging_assets_cloudfront_domain}-cert"
    Stack       = "assets-cloudfront"
    Environment = "staging"
  })
}

resource "aws_route53_record" "static_assets_staging_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.static_assets_staging.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      value = dvo.resource_record_value
      type  = dvo.resource_record_type
    }
  }

  zone_id         = aws_route53_zone.palad_ai.zone_id
  allow_overwrite = true
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.value]
}

resource "aws_acm_certificate_validation" "static_assets_staging" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.static_assets_staging.arn
  validation_record_fqdns = [for record in aws_route53_record.static_assets_staging_cert_validation : record.fqdn]
}

resource "aws_cloudfront_distribution" "static_assets_staging" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "CloudFront for staging static assets used by staging.palad.ai"
  aliases         = [local.staging_assets_cloudfront_domain]
  price_class     = "PriceClass_100"

  origin {
    domain_name = "staging.palad.ai"
    origin_id   = local.staging_assets_cloudfront_origin_id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id           = local.staging_assets_cloudfront_origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.managed_caching_disabled_staging.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.managed_simple_cors_staging.id
  }

  ordered_cache_behavior {
    path_pattern               = "/assets/*"
    target_origin_id           = local.staging_assets_cloudfront_origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.managed_caching_optimized_staging.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.managed_simple_cors_staging.id
  }

  ordered_cache_behavior {
    path_pattern               = "/vite/*"
    target_origin_id           = local.staging_assets_cloudfront_origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.managed_caching_optimized_staging.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.managed_simple_cors_staging.id
  }

  custom_error_response {
    error_code            = 400
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 403
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 500
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 502
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 503
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 504
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.static_assets_staging.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = merge(local.eks_common_tags, {
    Name        = "palad-static-assets-staging-cdn"
    Stack       = "assets-cloudfront"
    Environment = "staging"
  })
}

resource "aws_route53_record" "palad_ai_static_assets_staging" {
  zone_id = aws_route53_zone.palad_ai.zone_id
  name    = local.staging_assets_cloudfront_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.static_assets_staging.domain_name
    zone_id                = aws_cloudfront_distribution.static_assets_staging.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "palad_ai_static_assets_staging_ipv6" {
  zone_id = aws_route53_zone.palad_ai.zone_id
  name    = local.staging_assets_cloudfront_domain
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.static_assets_staging.domain_name
    zone_id                = aws_cloudfront_distribution.static_assets_staging.hosted_zone_id
    evaluate_target_health = false
  }
}

output "staging_assets_cloudfront_domain" {
  description = "Domain name of the CloudFront distribution for staging static assets"
  value       = local.staging_assets_cloudfront_domain
}

output "staging_assets_cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution for staging static assets"
  value       = aws_cloudfront_distribution.static_assets_staging.id
}
