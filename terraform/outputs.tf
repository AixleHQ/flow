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
