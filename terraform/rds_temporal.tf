resource "aws_db_subnet_group" "temporal_rds" {
  count = var.create_eks_cluster && var.create_managed_data_services && var.create_temporal_rds_instance ? 1 : 0

  name       = "${var.eks_cluster_name}-temporal-rds-subnets"
  subnet_ids = aws_subnet.eks_private[*].id

  tags = merge(local.eks_common_tags, {
    Name  = "${var.eks_cluster_name}-temporal-rds-subnets"
    Stack = "managed-data"
  })
}

resource "aws_security_group" "temporal_rds" {
  count = var.create_eks_cluster && var.create_managed_data_services && var.create_temporal_rds_instance ? 1 : 0

  name        = "${var.eks_cluster_name}-temporal-rds-sg"
  description = "Allow PostgreSQL from EKS VPC to Temporal RDS"
  vpc_id      = aws_vpc.eks[0].id

  ingress {
    from_port   = var.temporal_rds_port
    to_port     = var.temporal_rds_port
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
    Name  = "${var.eks_cluster_name}-temporal-rds-sg"
    Stack = "managed-data"
  })
}

resource "aws_db_instance" "temporal" {
  count = var.create_eks_cluster && var.create_managed_data_services && var.create_temporal_rds_instance ? 1 : 0

  identifier                 = var.temporal_rds_instance_identifier
  engine                     = "postgres"
  engine_version             = var.temporal_rds_engine_version
  instance_class             = var.temporal_rds_instance_class
  allocated_storage          = var.temporal_rds_allocated_storage
  max_allocated_storage      = var.temporal_rds_max_allocated_storage
  storage_type               = "gp3"
  storage_encrypted          = true
  db_name                    = var.temporal_rds_db_name
  username                   = var.temporal_rds_master_username
  password                   = var.temporal_rds_master_password
  port                       = var.temporal_rds_port
  db_subnet_group_name       = aws_db_subnet_group.temporal_rds[0].name
  vpc_security_group_ids     = [aws_security_group.temporal_rds[0].id]
  publicly_accessible        = false
  backup_retention_period    = var.temporal_rds_backup_retention_period
  backup_window              = var.temporal_rds_backup_window
  maintenance_window         = var.temporal_rds_maintenance_window
  auto_minor_version_upgrade = true
  deletion_protection        = var.temporal_rds_deletion_protection
  apply_immediately          = var.temporal_rds_apply_immediately
  skip_final_snapshot        = var.temporal_rds_skip_final_snapshot
  final_snapshot_identifier  = var.temporal_rds_skip_final_snapshot ? null : var.temporal_rds_final_snapshot_identifier
  copy_tags_to_snapshot      = true

  tags = merge(local.eks_common_tags, {
    Name  = var.temporal_rds_instance_identifier
    Stack = "managed-data"
  })

  lifecycle {
    precondition {
      condition     = try(length(trimspace(var.temporal_rds_master_password)) >= 16, false)
      error_message = "temporal_rds_master_password must be set and at least 16 characters when temporal RDS is enabled."
    }

    precondition {
      condition     = var.temporal_rds_skip_final_snapshot || try(length(trimspace(var.temporal_rds_final_snapshot_identifier)) > 0, false)
      error_message = "Set temporal_rds_final_snapshot_identifier when temporal_rds_skip_final_snapshot is false."
    }
  }
}
