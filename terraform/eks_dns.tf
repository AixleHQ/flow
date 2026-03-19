data "aws_lb" "eks_ingress_nlb" {
  count = var.create_eks_dns_records ? 1 : 0

  tags = {
    "kubernetes.io/service-name" = "${var.eks_ingress_namespace}/${var.eks_ingress_service_name}"
  }
}

data "aws_lb" "eks_staging_ingress_nlb" {
  count = var.create_eks_staging_dns_records ? 1 : 0

  tags = {
    "kubernetes.io/service-name" = "${var.eks_staging_ingress_namespace}/${var.eks_staging_ingress_service_name}"
  }
}

data "aws_lb" "eks_admin_ingress_nlb" {
  count = var.create_eks_admin_dns_record ? 1 : 0

  tags = {
    "kubernetes.io/service-name" = "${var.eks_admin_ingress_namespace}/${var.eks_admin_ingress_service_name}"
  }
}

resource "aws_route53_record" "palad_ai_root" {
  count   = var.create_eks_dns_records ? 1 : 0
  zone_id = aws_route53_zone.palad_ai.zone_id
  name    = "palad.ai"
  type    = "A"

  alias {
    name                   = data.aws_lb.eks_ingress_nlb[0].dns_name
    zone_id                = data.aws_lb.eks_ingress_nlb[0].zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "palad_ai_wildcard" {
  count   = var.create_eks_dns_records ? 1 : 0
  zone_id = aws_route53_zone.palad_ai.zone_id
  name    = "*.palad.ai"
  type    = "A"

  alias {
    name                   = data.aws_lb.eks_ingress_nlb[0].dns_name
    zone_id                = data.aws_lb.eks_ingress_nlb[0].zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "staging_palad_ai_root" {
  count   = var.create_eks_staging_dns_records ? 1 : 0
  zone_id = aws_route53_zone.palad_ai.zone_id
  name    = "staging.palad.ai"
  type    = "A"

  alias {
    name                   = data.aws_lb.eks_staging_ingress_nlb[0].dns_name
    zone_id                = data.aws_lb.eks_staging_ingress_nlb[0].zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "staging_palad_ai_wildcard" {
  count   = var.create_eks_staging_dns_records ? 1 : 0
  zone_id = aws_route53_zone.palad_ai.zone_id
  name    = "*.staging.palad.ai"
  type    = "A"

  alias {
    name                   = data.aws_lb.eks_staging_ingress_nlb[0].dns_name
    zone_id                = data.aws_lb.eks_staging_ingress_nlb[0].zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "palad_ai_traefik_admin" {
  count   = var.create_eks_admin_dns_record ? 1 : 0
  zone_id = aws_route53_zone.palad_ai.zone_id
  name    = var.eks_admin_dns_name
  type    = "A"

  alias {
    name                   = data.aws_lb.eks_admin_ingress_nlb[0].dns_name
    zone_id                = data.aws_lb.eks_admin_ingress_nlb[0].zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "palad_ai_temporal_admin" {
  count   = var.create_eks_admin_dns_record ? 1 : 0
  zone_id = aws_route53_zone.palad_ai.zone_id
  name    = var.eks_admin_temporal_dns_name
  type    = "A"

  alias {
    name                   = data.aws_lb.eks_admin_ingress_nlb[0].dns_name
    zone_id                = data.aws_lb.eks_admin_ingress_nlb[0].zone_id
    evaluate_target_health = true
  }
}
