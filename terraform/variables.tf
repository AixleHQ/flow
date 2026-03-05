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
  default     = ["34.1.250.211/32"]
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

variable "create_managed_data_services" {
  description = "Whether to create managed RDS PostgreSQL and ElastiCache Redis resources"
  type        = bool
  default     = true
}

variable "rds_instance_identifier" {
  description = "RDS instance identifier"
  type        = string
  default     = "palad-app-prod"
}

variable "rds_engine_version" {
  description = "PostgreSQL engine version for RDS"
  type        = string
  default     = "18.2"
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.medium"
}

variable "rds_allocated_storage" {
  description = "Initial storage size for RDS (GiB)"
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "Maximum autoscaled storage for RDS (GiB)"
  type        = number
  default     = 100
}

variable "rds_port" {
  description = "RDS PostgreSQL port"
  type        = number
  default     = 5432
}

variable "rds_db_name" {
  description = "Initial application database name"
  type        = string
  default     = "palad_production"
}

variable "rds_master_username" {
  description = "Master username for RDS PostgreSQL"
  type        = string
  default     = "postgres"
}

variable "rds_master_password" {
  description = "Master password for RDS PostgreSQL (set via tfvars or TF_VAR_rds_master_password)"
  type        = string
  sensitive   = true
  default     = null
}

variable "rds_backup_retention_period" {
  description = "Number of days to retain automatic RDS backups"
  type        = number
  default     = 7
}

variable "rds_backup_window" {
  description = "Preferred backup window for RDS in UTC, e.g. 03:00-04:00"
  type        = string
  default     = "03:00-04:00"
}

variable "rds_maintenance_window" {
  description = "Preferred maintenance window for RDS in UTC, e.g. Mon:04:00-Mon:05:00"
  type        = string
  default     = "Mon:04:00-Mon:05:00"
}

variable "rds_deletion_protection" {
  description = "Enable deletion protection for RDS instance"
  type        = bool
  default     = true
}

variable "rds_skip_final_snapshot" {
  description = "Whether to skip final snapshot when destroying RDS"
  type        = bool
  default     = true
}

variable "rds_final_snapshot_identifier" {
  description = "Final snapshot identifier used only when rds_skip_final_snapshot is false"
  type        = string
  default     = null
}

variable "rds_apply_immediately" {
  description = "Apply RDS modifications immediately instead of waiting for the maintenance window"
  type        = bool
  default     = false
}

variable "redis_replication_group_id" {
  description = "ElastiCache replication group identifier"
  type        = string
  default     = "palad-redis-prod"
}

variable "redis_engine_version" {
  description = "Redis engine version for ElastiCache"
  type        = string
  default     = "7.1"
}

variable "redis_node_type" {
  description = "Node type for ElastiCache Redis"
  type        = string
  default     = "cache.t3.small"
}

variable "redis_port" {
  description = "Redis port"
  type        = number
  default     = 6379
}

variable "redis_parameter_group_name" {
  description = "Parameter group name for Redis"
  type        = string
  default     = "default.redis7"
}

variable "redis_num_cache_clusters" {
  description = "Number of cache nodes in the replication group"
  type        = number
  default     = 1

  validation {
    condition     = var.redis_num_cache_clusters >= 1
    error_message = "redis_num_cache_clusters must be at least 1."
  }
}

variable "redis_transit_encryption_enabled" {
  description = "Enable in-transit encryption for Redis"
  type        = bool
  default     = false
}

variable "redis_auth_token" {
  description = "Optional Redis AUTH token (requires transit encryption)"
  type        = string
  sensitive   = true
  default     = null
}

variable "redis_snapshot_retention_limit" {
  description = "Number of days to retain Redis snapshots"
  type        = number
  default     = 1
}

variable "redis_maintenance_window" {
  description = "Preferred maintenance window for Redis in UTC, e.g. mon:05:00-mon:06:00"
  type        = string
  default     = "mon:05:00-mon:06:00"
}

variable "redis_apply_immediately" {
  description = "Apply Redis modifications immediately instead of waiting for the maintenance window"
  type        = bool
  default     = false
}
