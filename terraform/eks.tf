data "aws_availability_zones" "eks" {
  state = "available"
}

locals {
  eks_selected_azs = slice(data.aws_availability_zones.eks.names, 0, var.eks_az_count)
  eks_common_tags = {
    Project   = "palad"
    ManagedBy = "terraform"
    Stack     = "eks"
  }
}

resource "aws_vpc" "eks" {
  count = var.create_eks_cluster ? 1 : 0

  cidr_block           = var.eks_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.eks_common_tags, {
    Name = "${var.eks_cluster_name}-vpc"
  })
}

resource "aws_subnet" "eks_public" {
  count = var.create_eks_cluster ? var.eks_az_count : 0

  vpc_id                  = aws_vpc.eks[0].id
  cidr_block              = var.eks_public_subnet_cidrs[count.index]
  availability_zone       = local.eks_selected_azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.eks_common_tags, {
    Name                                            = "${var.eks_cluster_name}-public-${count.index + 1}"
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
    "kubernetes.io/role/elb"                        = "1"
  })
}

resource "aws_subnet" "eks_private" {
  count = var.create_eks_cluster ? var.eks_az_count : 0

  vpc_id            = aws_vpc.eks[0].id
  cidr_block        = var.eks_private_subnet_cidrs[count.index]
  availability_zone = local.eks_selected_azs[count.index]

  tags = merge(local.eks_common_tags, {
    Name                                            = "${var.eks_cluster_name}-private-${count.index + 1}"
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"               = "1"
  })
}

resource "aws_internet_gateway" "eks" {
  count = var.create_eks_cluster ? 1 : 0

  vpc_id = aws_vpc.eks[0].id

  tags = merge(local.eks_common_tags, {
    Name = "${var.eks_cluster_name}-igw"
  })
}

resource "aws_eip" "eks_nat" {
  count = var.create_eks_cluster ? 1 : 0

  domain = "vpc"

  tags = merge(local.eks_common_tags, {
    Name = "${var.eks_cluster_name}-nat-eip"
  })
}

resource "aws_nat_gateway" "eks" {
  count = var.create_eks_cluster ? 1 : 0

  allocation_id = aws_eip.eks_nat[0].id
  subnet_id     = aws_subnet.eks_public[0].id

  tags = merge(local.eks_common_tags, {
    Name = "${var.eks_cluster_name}-nat"
  })

  depends_on = [aws_internet_gateway.eks]
}

resource "aws_route_table" "eks_public" {
  count = var.create_eks_cluster ? 1 : 0

  vpc_id = aws_vpc.eks[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks[0].id
  }

  tags = merge(local.eks_common_tags, {
    Name = "${var.eks_cluster_name}-public-rt"
  })
}

resource "aws_route_table_association" "eks_public" {
  count = var.create_eks_cluster ? var.eks_az_count : 0

  subnet_id      = aws_subnet.eks_public[count.index].id
  route_table_id = aws_route_table.eks_public[0].id
}

resource "aws_route_table" "eks_private" {
  count = var.create_eks_cluster ? 1 : 0

  vpc_id = aws_vpc.eks[0].id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.eks[0].id
  }

  tags = merge(local.eks_common_tags, {
    Name = "${var.eks_cluster_name}-private-rt"
  })
}

resource "aws_route_table_association" "eks_private" {
  count = var.create_eks_cluster ? var.eks_az_count : 0

  subnet_id      = aws_subnet.eks_private[count.index].id
  route_table_id = aws_route_table.eks_private[0].id
}

resource "aws_iam_role" "eks_cluster" {
  count = var.create_eks_cluster ? 1 : 0

  name = "${var.eks_cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(local.eks_common_tags, {
    Name = "${var.eks_cluster_name}-cluster-role"
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  count = var.create_eks_cluster ? 1 : 0

  role       = aws_iam_role.eks_cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cluster_vpc_resource_controller" {
  count = var.create_eks_cluster ? 1 : 0

  role       = aws_iam_role.eks_cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

resource "aws_cloudwatch_log_group" "eks_cluster" {
  count = var.create_eks_cluster ? 1 : 0

  name              = "/aws/eks/${var.eks_cluster_name}/cluster"
  retention_in_days = var.eks_cluster_log_retention_days

  tags = merge(local.eks_common_tags, {
    Name = "${var.eks_cluster_name}-control-plane-logs"
  })
}

resource "aws_eks_cluster" "main" {
  count = var.create_eks_cluster ? 1 : 0

  name     = var.eks_cluster_name
  role_arn = aws_iam_role.eks_cluster[0].arn
  version  = var.eks_cluster_version

  enabled_cluster_log_types = var.eks_cluster_log_types

  vpc_config {
    subnet_ids              = concat(aws_subnet.eks_private[*].id, aws_subnet.eks_public[*].id)
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.eks_public_access_cidrs
  }

  tags = merge(local.eks_common_tags, {
    Name = var.eks_cluster_name
  })

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_cluster_vpc_resource_controller,
    aws_cloudwatch_log_group.eks_cluster
  ]
}

resource "aws_iam_role" "eks_nodes" {
  count = var.create_eks_cluster ? 1 : 0

  name = "${var.eks_cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(local.eks_common_tags, {
    Name = "${var.eks_cluster_name}-node-role"
  })
}

resource "aws_iam_role_policy_attachment" "eks_nodes_worker_policy" {
  count = var.create_eks_cluster ? 1 : 0

  role       = aws_iam_role.eks_nodes[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_nodes_cni_policy" {
  count = var.create_eks_cluster ? 1 : 0

  role       = aws_iam_role.eks_nodes[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_nodes_ecr_policy" {
  count = var.create_eks_cluster ? 1 : 0

  role       = aws_iam_role.eks_nodes[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "eks_nodes_ssm_policy" {
  count = var.create_eks_cluster ? 1 : 0

  role       = aws_iam_role.eks_nodes[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_eks_node_group" "main" {
  count = var.create_eks_cluster ? 1 : 0

  cluster_name    = aws_eks_cluster.main[0].name
  node_group_name = var.eks_node_group_name
  node_role_arn   = aws_iam_role.eks_nodes[0].arn
  subnet_ids      = aws_subnet.eks_private[*].id
  ami_type        = var.eks_node_ami_type
  capacity_type   = var.eks_node_capacity_type
  instance_types  = var.eks_node_instance_types

  scaling_config {
    desired_size = var.eks_node_desired_size
    max_size     = var.eks_node_max_size
    min_size     = var.eks_node_min_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = merge(local.eks_common_tags, {
    Name                                                = "${var.eks_cluster_name}-${var.eks_node_group_name}"
    "k8s.io/cluster-autoscaler/enabled"                 = "true"
    "k8s.io/cluster-autoscaler/${var.eks_cluster_name}" = "owned"
  })

  lifecycle {
    precondition {
      condition     = var.eks_node_min_size <= var.eks_node_desired_size && var.eks_node_desired_size <= var.eks_node_max_size
      error_message = "EKS node scaling must satisfy min <= desired <= max."
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_nodes_worker_policy,
    aws_iam_role_policy_attachment.eks_nodes_cni_policy,
    aws_iam_role_policy_attachment.eks_nodes_ecr_policy,
    aws_iam_role_policy_attachment.eks_nodes_ssm_policy
  ]
}

data "tls_certificate" "eks_oidc" {
  count = var.create_eks_cluster ? 1 : 0

  url = aws_eks_cluster.main[0].identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  count = var.create_eks_cluster ? 1 : 0

  url             = aws_eks_cluster.main[0].identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc[0].certificates[0].sha1_fingerprint]

  tags = merge(local.eks_common_tags, {
    Name = "${var.eks_cluster_name}-oidc"
  })
}

data "aws_iam_policy_document" "eks_cluster_autoscaler_irsa_assume_role" {
  count = var.create_eks_cluster ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {
      type = "Federated"
      identifiers = [
        aws_iam_openid_connect_provider.eks[0].arn
      ]
    }

    condition {
      test = "StringEquals"
      values = [
        "sts.amazonaws.com"
      ]
      variable = "${replace(aws_eks_cluster.main[0].identity[0].oidc[0].issuer, "https://", "")}:aud"
    }

    condition {
      test = "StringEquals"
      values = [
        "system:serviceaccount:kube-system:cluster-autoscaler"
      ]
      variable = "${replace(aws_eks_cluster.main[0].identity[0].oidc[0].issuer, "https://", "")}:sub"
    }
  }
}

resource "aws_iam_role" "eks_cluster_autoscaler" {
  count = var.create_eks_cluster ? 1 : 0

  name               = "${var.eks_cluster_name}-cluster-autoscaler-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_autoscaler_irsa_assume_role[0].json

  tags = merge(local.eks_common_tags, {
    Name = "${var.eks_cluster_name}-cluster-autoscaler-role"
  })
}

data "aws_iam_policy_document" "eks_cluster_autoscaler" {
  count = var.create_eks_cluster ? 1 : 0

  statement {
    sid    = "AllowAutoscalerRead"
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeImages",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:GetInstanceTypesFromInstanceRequirements",
      "eks:DescribeNodegroup"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowAutoscalerScaleNodeGroups"
    effect = "Allow"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup"
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/enabled"
      values   = ["true"]
    }

    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/${var.eks_cluster_name}"
      values   = ["owned"]
    }
  }
}

resource "aws_iam_policy" "eks_cluster_autoscaler" {
  count = var.create_eks_cluster ? 1 : 0

  name   = "${var.eks_cluster_name}-cluster-autoscaler-policy"
  policy = data.aws_iam_policy_document.eks_cluster_autoscaler[0].json

  tags = merge(local.eks_common_tags, {
    Name = "${var.eks_cluster_name}-cluster-autoscaler-policy"
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_autoscaler" {
  count = var.create_eks_cluster ? 1 : 0

  role       = aws_iam_role.eks_cluster_autoscaler[0].name
  policy_arn = aws_iam_policy.eks_cluster_autoscaler[0].arn
}

data "aws_iam_policy_document" "eks_ebs_csi_irsa_assume_role" {
  count = var.create_eks_cluster ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {
      type = "Federated"
      identifiers = [
        aws_iam_openid_connect_provider.eks[0].arn
      ]
    }

    condition {
      test = "StringEquals"
      values = [
        "sts.amazonaws.com"
      ]
      variable = "${replace(aws_eks_cluster.main[0].identity[0].oidc[0].issuer, "https://", "")}:aud"
    }

    condition {
      test = "StringEquals"
      values = [
        "system:serviceaccount:kube-system:ebs-csi-controller-sa"
      ]
      variable = "${replace(aws_eks_cluster.main[0].identity[0].oidc[0].issuer, "https://", "")}:sub"
    }
  }
}

resource "aws_iam_role" "eks_ebs_csi" {
  count = var.create_eks_cluster ? 1 : 0

  name               = "${var.eks_cluster_name}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.eks_ebs_csi_irsa_assume_role[0].json

  tags = merge(local.eks_common_tags, {
    Name = "${var.eks_cluster_name}-ebs-csi-role"
  })
}

resource "aws_iam_role_policy_attachment" "eks_ebs_csi_driver" {
  count = var.create_eks_cluster ? 1 : 0

  role       = aws_iam_role.eks_ebs_csi[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "eks_ebs_csi" {
  count = var.create_eks_cluster ? 1 : 0

  cluster_name                = aws_eks_cluster.main[0].name
  addon_name                  = "aws-ebs-csi-driver"
  service_account_role_arn    = aws_iam_role.eks_ebs_csi[0].arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_iam_role_policy_attachment.eks_ebs_csi_driver
  ]
}

data "aws_iam_policy_document" "eks_traefik_irsa_assume_role" {
  count = var.create_eks_cluster ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {
      type = "Federated"
      identifiers = [
        aws_iam_openid_connect_provider.eks[0].arn
      ]
    }

    condition {
      test = "StringEquals"
      values = [
        "sts.amazonaws.com"
      ]
      variable = "${replace(aws_eks_cluster.main[0].identity[0].oidc[0].issuer, "https://", "")}:aud"
    }

    condition {
      test = "StringEquals"
      values = [
        "system:serviceaccount:${var.eks_traefik_namespace}:${var.eks_traefik_service_account_name}"
      ]
      variable = "${replace(aws_eks_cluster.main[0].identity[0].oidc[0].issuer, "https://", "")}:sub"
    }
  }
}

resource "aws_iam_role" "eks_traefik_dns" {
  count = var.create_eks_cluster ? 1 : 0

  name               = "${var.eks_cluster_name}-traefik-dns-role"
  assume_role_policy = data.aws_iam_policy_document.eks_traefik_irsa_assume_role[0].json

  tags = merge(local.eks_common_tags, {
    Name = "${var.eks_cluster_name}-traefik-dns-role"
  })
}

data "aws_iam_policy_document" "eks_traefik_dns" {
  count = var.create_eks_cluster ? 1 : 0

  statement {
    sid    = "AllowChangeAcmeRecordsInPaladZone"
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets"
    ]
    resources = [
      aws_route53_zone.palad_ai.arn
    ]
  }

  statement {
    sid    = "AllowRoute53LookupAndChangeStatus"
    effect = "Allow"
    actions = [
      "route53:ListHostedZonesByName",
      "route53:GetChange"
    ]
    resources = [
      "*"
    ]
  }
}

resource "aws_iam_policy" "eks_traefik_dns" {
  count = var.create_eks_cluster ? 1 : 0

  name   = "${var.eks_cluster_name}-traefik-dns-policy"
  policy = data.aws_iam_policy_document.eks_traefik_dns[0].json

  tags = merge(local.eks_common_tags, {
    Name = "${var.eks_cluster_name}-traefik-dns-policy"
  })
}

resource "aws_iam_role_policy_attachment" "eks_traefik_dns" {
  count = var.create_eks_cluster ? 1 : 0

  role       = aws_iam_role.eks_traefik_dns[0].name
  policy_arn = aws_iam_policy.eks_traefik_dns[0].arn
}
