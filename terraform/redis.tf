resource "aws_elasticache_subnet_group" "redis" {
  count = var.create_eks_cluster && var.create_managed_data_services ? 1 : 0

  name       = "${var.eks_cluster_name}-redis-subnets"
  subnet_ids = aws_subnet.eks_private[*].id

  tags = merge(local.eks_common_tags, {
    Name  = "${var.eks_cluster_name}-redis-subnets"
    Stack = "managed-data"
  })
}

resource "aws_security_group" "redis" {
  count = var.create_eks_cluster && var.create_managed_data_services ? 1 : 0

  name        = "${var.eks_cluster_name}-redis-sg"
  description = "Allow Redis from EKS VPC"
  vpc_id      = aws_vpc.eks[0].id

  ingress {
    from_port   = var.redis_port
    to_port     = var.redis_port
    protocol    = "tcp"
    cidr_blocks = [var.eks_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.eks_common_tags, {
    Name  = "${var.eks_cluster_name}-redis-sg"
    Stack = "managed-data"
  })
}

resource "aws_elasticache_replication_group" "redis" {
  count = var.create_eks_cluster && var.create_managed_data_services ? 1 : 0

  replication_group_id       = var.redis_replication_group_id
  description                = "Redis for ${var.eks_cluster_name}"
  engine                     = "redis"
  engine_version             = var.redis_engine_version
  node_type                  = var.redis_node_type
  port                       = var.redis_port
  parameter_group_name       = var.redis_parameter_group_name
  num_cache_clusters         = var.redis_num_cache_clusters
  subnet_group_name          = aws_elasticache_subnet_group.redis[0].name
  security_group_ids         = [aws_security_group.redis[0].id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = var.redis_transit_encryption_enabled
  auth_token                 = var.redis_auth_token
  automatic_failover_enabled = var.redis_num_cache_clusters > 1
  multi_az_enabled           = var.redis_num_cache_clusters > 1
  auto_minor_version_upgrade = true
  maintenance_window         = var.redis_maintenance_window
  snapshot_retention_limit   = var.redis_snapshot_retention_limit
  apply_immediately          = var.redis_apply_immediately

  tags = merge(local.eks_common_tags, {
    Name  = var.redis_replication_group_id
    Stack = "managed-data"
  })

  lifecycle {
    precondition {
      condition     = var.redis_auth_token == null || var.redis_transit_encryption_enabled
      error_message = "redis_auth_token requires redis_transit_encryption_enabled=true."
    }
  }
}
