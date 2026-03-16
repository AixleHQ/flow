locals {
  assets_cloudfront_origin_id = "palad-static-assets-origin"
}

data "aws_cloudfront_cache_policy" "managed_caching_optimized" {
  count = var.create_assets_cloudfront_distribution ? 1 : 0
  name  = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "managed_caching_disabled" {
  count = var.create_assets_cloudfront_distribution ? 1 : 0
  name  = "Managed-CachingDisabled"
}

data "aws_cloudfront_response_headers_policy" "managed_simple_cors" {
  count = var.create_assets_cloudfront_distribution ? 1 : 0
  name  = "Managed-SimpleCORS"
}

resource "aws_acm_certificate" "static_assets" {
  count    = var.create_assets_cloudfront_distribution ? 1 : 0
  provider = aws.us_east_1

  domain_name       = var.assets_cloudfront_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.eks_common_tags, {
    Name  = "${var.assets_cloudfront_domain_name}-cert"
    Stack = "assets-cloudfront"
  })
}

resource "aws_route53_record" "static_assets_cert_validation" {
  for_each = var.create_assets_cloudfront_distribution ? {
    for dvo in aws_acm_certificate.static_assets[0].domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      value = dvo.resource_record_value
      type  = dvo.resource_record_type
    }
  } : {}

  zone_id         = aws_route53_zone.palad_ai.zone_id
  allow_overwrite = true
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.value]
}

resource "aws_acm_certificate_validation" "static_assets" {
  count    = var.create_assets_cloudfront_distribution ? 1 : 0
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.static_assets[0].arn
  validation_record_fqdns = [for record in aws_route53_record.static_assets_cert_validation : record.fqdn]
}

resource "aws_cloudfront_distribution" "static_assets" {
  count = var.create_assets_cloudfront_distribution ? 1 : 0

  enabled         = true
  is_ipv6_enabled = true
  comment         = "CloudFront for static assets used by palad.ai web app"
  aliases         = [var.assets_cloudfront_domain_name]
  price_class     = var.assets_cloudfront_price_class

  origin {
    domain_name = var.assets_cloudfront_origin_domain_name
    origin_id   = local.assets_cloudfront_origin_id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id           = local.assets_cloudfront_origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.managed_caching_disabled[0].id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.managed_simple_cors[0].id
  }

  ordered_cache_behavior {
    path_pattern               = "/assets/*"
    target_origin_id           = local.assets_cloudfront_origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.managed_caching_optimized[0].id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.managed_simple_cors[0].id
  }

  ordered_cache_behavior {
    path_pattern               = "/vite/*"
    target_origin_id           = local.assets_cloudfront_origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.managed_caching_optimized[0].id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.managed_simple_cors[0].id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.static_assets[0].certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = merge(local.eks_common_tags, {
    Name  = "palad-static-assets-cdn"
    Stack = "assets-cloudfront"
  })
}

resource "aws_route53_record" "palad_ai_static_assets" {
  count   = var.create_assets_cloudfront_distribution ? 1 : 0
  zone_id = aws_route53_zone.palad_ai.zone_id
  name    = var.assets_cloudfront_domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.static_assets[0].domain_name
    zone_id                = aws_cloudfront_distribution.static_assets[0].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "palad_ai_static_assets_ipv6" {
  count   = var.create_assets_cloudfront_distribution ? 1 : 0
  zone_id = aws_route53_zone.palad_ai.zone_id
  name    = var.assets_cloudfront_domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.static_assets[0].domain_name
    zone_id                = aws_cloudfront_distribution.static_assets[0].hosted_zone_id
    evaluate_target_health = false
  }
}
