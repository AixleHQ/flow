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

# EC2 outputs
output "k3s_instance_id" {
  description = "EC2 instance ID for k3s cluster"
  value       = try(aws_instance.k3s[0].id, null)
}

output "k3s_instance_public_ip" {
  description = "Public Elastic IP of the k3s instance"
  value       = try(aws_eip.k3s[0].public_ip, null)
}

output "k3s_instance_private_ip" {
  description = "Private IP of the k3s instance"
  value       = try(aws_instance.k3s[0].private_ip, null)
}

output "k3s_instance_type" {
  description = "Instance type of the k3s cluster"
  value       = try(aws_instance.k3s[0].instance_type, null)
}

output "k3s_security_group_id" {
  description = "Security group ID for k3s instance"
  value       = aws_security_group.k3s_sg.id
}

output "k3s_ssh_command" {
  description = "SSH command to connect to k3s instance"
  value       = try("ssh -i <your-key-pair> ubuntu@${aws_eip.k3s[0].public_ip}", null)
}

# DNS outputs
output "palad_ai_dns_record" {
  description = "A record for palad.ai pointing to k3s instance"
  value       = try(aws_route53_record.palad_ai_root[0].fqdn, null)
}

output "palad_ai_wildcard_dns_record" {
  description = "Wildcard A record for *.palad.ai pointing to k3s instance"
  value       = try(aws_route53_record.palad_ai_wildcard[0].fqdn, null)
}

output "palad_ai_instance_ip" {
  description = "IP address that palad.ai resolves to"
  value       = try(aws_eip.k3s[0].public_ip, null)
}
