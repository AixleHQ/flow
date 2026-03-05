resource "aws_db_subnet_group" "rds" {
  count = var.create_eks_cluster && var.create_managed_data_services ? 1 : 0

  name       = "${var.eks_cluster_name}-rds-subnets"
  subnet_ids = aws_subnet.eks_private[*].id

  tags = merge(local.eks_common_tags, {
    Name  = "${var.eks_cluster_name}-rds-subnets"
    Stack = "managed-data"
  })
}

resource "aws_security_group" "rds" {
  count = var.create_eks_cluster && var.create_managed_data_services ? 1 : 0

  name        = "${var.eks_cluster_name}-rds-sg"
  description = "Allow PostgreSQL from EKS VPC"
  vpc_id      = aws_vpc.eks[0].id

  ingress {
    from_port   = var.rds_port
    to_port     = var.rds_port
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
    Name  = "${var.eks_cluster_name}-rds-sg"
    Stack = "managed-data"
  })
}

resource "aws_db_instance" "app" {
  count = var.create_eks_cluster && var.create_managed_data_services ? 1 : 0

  identifier                 = var.rds_instance_identifier
  engine                     = "postgres"
  engine_version             = var.rds_engine_version
  instance_class             = var.rds_instance_class
  allocated_storage          = var.rds_allocated_storage
  max_allocated_storage      = var.rds_max_allocated_storage
  storage_type               = "gp3"
  storage_encrypted          = true
  db_name                    = var.rds_db_name
  username                   = var.rds_master_username
  password                   = var.rds_master_password
  port                       = var.rds_port
  db_subnet_group_name       = aws_db_subnet_group.rds[0].name
  vpc_security_group_ids     = [aws_security_group.rds[0].id]
  publicly_accessible        = false
  backup_retention_period    = var.rds_backup_retention_period
  backup_window              = var.rds_backup_window
  maintenance_window         = var.rds_maintenance_window
  auto_minor_version_upgrade = true
  deletion_protection        = var.rds_deletion_protection
  apply_immediately          = var.rds_apply_immediately
  skip_final_snapshot        = var.rds_skip_final_snapshot
  final_snapshot_identifier  = var.rds_skip_final_snapshot ? null : var.rds_final_snapshot_identifier
  copy_tags_to_snapshot      = true

  tags = merge(local.eks_common_tags, {
    Name  = var.rds_instance_identifier
    Stack = "managed-data"
  })

  lifecycle {
    precondition {
      condition     = try(length(trimspace(var.rds_master_password)) >= 16, false)
      error_message = "rds_master_password must be set and at least 16 characters when managed data services are enabled."
    }

    precondition {
      condition     = var.rds_skip_final_snapshot || try(length(trimspace(var.rds_final_snapshot_identifier)) > 0, false)
      error_message = "Set rds_final_snapshot_identifier when rds_skip_final_snapshot is false."
    }
  }
}
