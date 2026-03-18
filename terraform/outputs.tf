output "tfstate_bucket_name" {
  description = "Name of the S3 bucket for storing Terraform state"
  value       = aws_s3_bucket.tfstate.id
}

output "tfstate_bucket_arn" {
  description = "ARN of the S3 bucket for storing Terraform state"
  value       = aws_s3_bucket.tfstate.arn
}

output "tfstate_bucket_region" {
  description = "Region of the S3 bucket for storing Terraform state"
  value       = aws_s3_bucket.tfstate.region
}

output "assets_bucket_name" {
  description = "Name of the S3 bucket used by application asset uploads"
  value       = var.assets_bucket_name
}

output "assets_bucket_arn" {
  description = "ARN of the S3 bucket used by application asset uploads"
  value       = local.assets_bucket_arn
}

output "assets_bucket_region" {
  description = "Region of the S3 bucket used by application asset uploads"
  value       = var.aws_region
}

output "cloudfront_static_assets_distribution_id" {
  description = "CloudFront distribution ID for static Rails/Vite assets"
  value       = try(aws_cloudfront_distribution.static_assets[0].id, null)
}

output "cloudfront_static_assets_domain_name" {
  description = "CloudFront domain name for static Rails/Vite assets"
  value       = try(aws_cloudfront_distribution.static_assets[0].domain_name, null)
}

output "cloudfront_static_assets_alias_domain_name" {
  description = "Custom DNS hostname for static Rails/Vite assets"
  value       = try(aws_route53_record.palad_ai_static_assets[0].fqdn, null)
}

output "cloudfront_static_assets_url" {
  description = "HTTPS URL base for static Rails/Vite assets"
  value       = try("https://${trim(aws_route53_record.palad_ai_static_assets[0].fqdn, ".")}", null)
}

output "eks_assets_irsa_role_arn" {
  description = "IAM role ARN for IRSA access to the assets S3 bucket from app workloads"
  value       = try(aws_iam_role.eks_assets[0].arn, null)
}

# Route53 outputs
output "route53_zone_id" {
  description = "Route53 hosted zone ID for palad.ai"
  value       = aws_route53_zone.palad_ai.zone_id
}

output "route53_zone_nameservers" {
  description = "Name servers for palad.ai zone"
  value       = aws_route53_zone.palad_ai.name_servers
}

output "eks_ingress_nlb_dns_name" {
  description = "DNS name of the EKS ingress NLB discovered from kubernetes.io/service-name tag"
  value       = try(data.aws_lb.eks_ingress_nlb[0].dns_name, null)
}

output "eks_staging_ingress_nlb_dns_name" {
  description = "DNS name of the staging EKS ingress NLB discovered from kubernetes.io/service-name tag"
  value       = try(data.aws_lb.eks_staging_ingress_nlb[0].dns_name, null)
}

output "eks_admin_ingress_nlb_dns_name" {
  description = "DNS name of the restricted EKS admin ingress NLB"
  value       = try(data.aws_lb.eks_admin_ingress_nlb[0].dns_name, null)
}

output "palad_ai_dns_record" {
  description = "Route53 A record for palad.ai pointing to EKS ingress NLB"
  value       = try(aws_route53_record.palad_ai_root[0].fqdn, null)
}

output "palad_ai_wildcard_dns_record" {
  description = "Route53 wildcard A record for *.palad.ai pointing to EKS ingress NLB"
  value       = try(aws_route53_record.palad_ai_wildcard[0].fqdn, null)
}

output "staging_palad_ai_dns_record" {
  description = "Route53 A record for staging.palad.ai pointing to the staging EKS ingress NLB"
  value       = try(aws_route53_record.staging_palad_ai_root[0].fqdn, null)
}

output "staging_palad_ai_wildcard_dns_record" {
  description = "Route53 wildcard A record for *.staging.palad.ai pointing to the staging EKS ingress NLB"
  value       = try(aws_route53_record.staging_palad_ai_wildcard[0].fqdn, null)
}

output "palad_ai_traefik_admin_dns_record" {
  description = "Route53 A record for traefik.palad.ai pointing to restricted EKS admin ingress NLB"
  value       = try(aws_route53_record.palad_ai_traefik_admin[0].fqdn, null)
}

output "palad_ai_temporal_admin_dns_record" {
  description = "Route53 A record for temporal.palad.ai pointing to restricted EKS admin ingress NLB"
  value       = try(aws_route53_record.palad_ai_temporal_admin[0].fqdn, null)
}

# EKS outputs
output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = try(aws_eks_cluster.main[0].name, null)
}

output "eks_cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = try(aws_eks_cluster.main[0].arn, null)
}

output "eks_cluster_endpoint" {
  description = "Kubernetes API endpoint for EKS cluster"
  value       = try(aws_eks_cluster.main[0].endpoint, null)
}

output "eks_cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  value       = try(aws_eks_cluster.main[0].version, null)
}

output "eks_cluster_oidc_issuer" {
  description = "OIDC issuer URL for IRSA"
  value       = try(aws_eks_cluster.main[0].identity[0].oidc[0].issuer, null)
}

output "eks_oidc_provider_arn" {
  description = "IAM OIDC provider ARN for IRSA"
  value       = try(aws_iam_openid_connect_provider.eks[0].arn, null)
}

output "eks_traefik_dns_irsa_role_arn" {
  description = "IAM role ARN for Traefik IRSA Route53 DNS challenge access"
  value       = try(aws_iam_role.eks_traefik_dns[0].arn, null)
}

output "eks_cluster_autoscaler_irsa_role_arn" {
  description = "IAM role ARN for Cluster Autoscaler IRSA access"
  value       = try(aws_iam_role.eks_cluster_autoscaler[0].arn, null)
}

output "eks_node_group_name" {
  description = "Managed node group name"
  value       = try(aws_eks_node_group.main[0].node_group_name, null)
}

output "eks_vpc_id" {
  description = "VPC ID for EKS cluster"
  value       = try(aws_vpc.eks[0].id, null)
}

output "eks_private_subnet_ids" {
  description = "Private subnet IDs used by EKS nodes"
  value       = aws_subnet.eks_private[*].id
}

output "eks_public_subnet_ids" {
  description = "Public subnet IDs used by EKS load balancers/NAT"
  value       = aws_subnet.eks_public[*].id
}

output "eks_kubeconfig_command" {
  description = "Command to update local kubeconfig for this EKS cluster"
  value       = try("aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main[0].name}", null)
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint hostname"
  value       = try(aws_db_instance.app[0].address, null)
}

output "rds_endpoint_with_port" {
  description = "RDS PostgreSQL endpoint with port"
  value       = try(aws_db_instance.app[0].endpoint, null)
}

output "rds_port" {
  description = "RDS PostgreSQL port"
  value       = var.rds_port
}

output "rds_db_name" {
  description = "Application database name configured for RDS"
  value       = var.rds_db_name
}

output "rds_master_username" {
  description = "Master username for RDS"
  value       = var.rds_master_username
}

output "temporal_rds_endpoint" {
  description = "Temporal RDS PostgreSQL endpoint hostname"
  value       = try(aws_db_instance.temporal[0].address, null)
}

output "temporal_rds_endpoint_with_port" {
  description = "Temporal RDS PostgreSQL endpoint with port"
  value       = try(aws_db_instance.temporal[0].endpoint, null)
}

output "temporal_rds_port" {
  description = "Temporal RDS PostgreSQL port"
  value       = var.temporal_rds_port
}

output "temporal_rds_db_name" {
  description = "Initial Temporal RDS database name"
  value       = var.temporal_rds_db_name
}

output "temporal_rds_master_username" {
  description = "Master username for Temporal RDS"
  value       = var.temporal_rds_master_username
}

output "redis_primary_endpoint" {
  description = "Primary endpoint hostname for ElastiCache Redis"
  value       = try(aws_elasticache_replication_group.redis[0].primary_endpoint_address, null)
}

output "redis_reader_endpoint" {
  description = "Reader endpoint hostname for ElastiCache Redis"
  value       = try(aws_elasticache_replication_group.redis[0].reader_endpoint_address, null)
}

output "redis_port" {
  description = "Redis port"
  value       = var.redis_port
}

output "ci_runner_instance_id" {
  description = "Instance ID of the GitHub Actions CI runner"
  value       = try(aws_instance.ci_runner[0].id, null)
}

output "ci_runner_private_ip" {
  description = "Private IP address of the GitHub Actions CI runner"
  value       = try(aws_instance.ci_runner[0].private_ip, null)
}

output "ci_runner_public_ip" {
  description = "Public IP address of the GitHub Actions CI runner when placed in a public subnet"
  value       = try(aws_instance.ci_runner[0].public_ip, null)
}

output "ci_runner_security_group_id" {
  description = "Security group ID attached to the GitHub Actions CI runner"
  value       = try(aws_security_group.ci_runner[0].id, null)
}

output "ci_runner_ssm_start_session_command" {
  description = "AWS CLI command to open an SSM shell session to the CI runner"
  value       = try("aws ssm start-session --region ${var.aws_region} --target ${aws_instance.ci_runner[0].id}", null)
}

output "ci_runner_ssm_parameter_names" {
  description = "SSM parameter names used for the GitHub runner bootstrap credentials"
  value = {
    app_id          = var.ci_runner_github_app_id_ssm_parameter_name
    installation_id = var.ci_runner_github_app_installation_id_ssm_parameter_name
    private_key     = var.ci_runner_github_app_private_key_ssm_parameter_name
  }
}

output "redis_url_database_1" {
  description = "Redis URL for app config (DB 1)"
  value       = try("redis://${aws_elasticache_replication_group.redis[0].primary_endpoint_address}:${var.redis_port}/1", null)
}
