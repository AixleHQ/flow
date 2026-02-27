variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "tfstate_bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  type        = string
  default     = "palad-tfstate"
}

variable "create_eks_cluster" {
  description = "Whether to create the EKS cluster and networking resources"
  type        = bool
  default     = true
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "palad-eks"
}

variable "eks_cluster_version" {
  description = "Kubernetes version for the EKS control plane"
  type        = string
  default     = "1.35"
}

variable "eks_az_count" {
  description = "Number of availability zones to use for EKS networking"
  type        = number
  default     = 2

  validation {
    condition     = var.eks_az_count >= 2 && var.eks_az_count <= 3
    error_message = "eks_az_count must be between 2 and 3."
  }
}

variable "eks_vpc_cidr" {
  description = "CIDR block for the EKS VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "eks_private_subnet_cidrs" {
  description = "Private subnet CIDRs for EKS node groups and internal load balancers"
  type        = list(string)
  default     = ["10.10.1.0/24", "10.10.2.0/24", "10.10.3.0/24"]

  validation {
    condition     = length(var.eks_private_subnet_cidrs) >= var.eks_az_count
    error_message = "eks_private_subnet_cidrs must include at least eks_az_count CIDRs."
  }
}

variable "eks_public_subnet_cidrs" {
  description = "Public subnet CIDRs for NAT and internet-facing load balancers"
  type        = list(string)
  default     = ["10.10.101.0/24", "10.10.102.0/24", "10.10.103.0/24"]

  validation {
    condition     = length(var.eks_public_subnet_cidrs) >= var.eks_az_count
    error_message = "eks_public_subnet_cidrs must include at least eks_az_count CIDRs."
  }
}

variable "eks_public_access_cidrs" {
  description = "Allowed CIDR blocks for the public EKS API endpoint"
  type        = list(string)
  default     = ["212.58.121.200/32", "35.204.251.191/32"]
}

variable "eks_node_group_name" {
  description = "Managed node group name"
  type        = string
  default     = "palad-on-demand"
}

variable "eks_node_instance_types" {
  description = "EC2 instance types for EKS managed node group"
  type        = list(string)
  default     = ["t3.large"]
}

variable "eks_node_ami_type" {
  description = "AMI type for EKS managed nodes"
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "eks_node_capacity_type" {
  description = "Capacity type for EKS managed nodes (ON_DEMAND or SPOT)"
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.eks_node_capacity_type)
    error_message = "eks_node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "eks_node_desired_size" {
  description = "Desired number of nodes in the EKS managed node group"
  type        = number
  default     = 2
}

variable "eks_node_min_size" {
  description = "Minimum number of nodes in the EKS managed node group"
  type        = number
  default     = 2
}

variable "eks_node_max_size" {
  description = "Maximum number of nodes in the EKS managed node group"
  type        = number
  default     = 4
}

variable "eks_cluster_log_types" {
  description = "EKS control plane logs to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "eks_cluster_log_retention_days" {
  description = "CloudWatch log retention in days for EKS control plane logs"
  type        = number
  default     = 14
}

variable "create_eks_dns_records" {
  description = "Whether to create Route53 records for palad.ai to point at the EKS ingress NLB"
  type        = bool
  default     = true
}

variable "eks_ingress_namespace" {
  description = "Namespace of the Kubernetes Service that exposes ingress via NLB"
  type        = string
  default     = "palad"
}

variable "eks_ingress_service_name" {
  description = "Name of the Kubernetes Service that exposes ingress via NLB"
  type        = string
  default     = "traefik"
}

variable "create_eks_admin_dns_record" {
  description = "Whether to create a dedicated Route53 record for traefik.palad.ai pointing to restricted admin NLB"
  type        = bool
  default     = true
}

variable "eks_admin_ingress_namespace" {
  description = "Namespace of the restricted admin Kubernetes Service exposed via NLB"
  type        = string
  default     = "palad"
}

variable "eks_admin_ingress_service_name" {
  description = "Name of the restricted admin Kubernetes Service exposed via NLB"
  type        = string
  default     = "traefik-admin"
}

variable "eks_admin_dns_name" {
  description = "DNS hostname for restricted admin ingress"
  type        = string
  default     = "traefik.palad.ai"
}

variable "eks_admin_temporal_dns_name" {
  description = "DNS hostname for restricted temporal UI ingress"
  type        = string
  default     = "temporal.palad.ai"
}

variable "eks_traefik_namespace" {
  description = "Namespace of the Traefik service account used for IRSA"
  type        = string
  default     = "palad"
}

variable "eks_traefik_service_account_name" {
  description = "Name of the Traefik service account used for IRSA"
  type        = string
  default     = "traefik"
}
