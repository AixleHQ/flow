data "aws_caller_identity" "current" {}

data "aws_ami" "ci_runner" {
  count = var.create_ci_runner_instance && var.create_eks_cluster ? 1 : 0

  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  ci_runner_repo_url = "https://github.com/${var.ci_runner_github_owner}/${var.ci_runner_github_repo}"
  ci_runner_tags = merge(local.eks_common_tags, var.ci_runner_tags, {
    Name      = var.ci_runner_instance_name
    Component = "github-actions-runner"
    Stack     = "github-runner"
  })
  ci_runner_subnet_ids = var.ci_runner_subnet_type == "public" ? aws_subnet.eks_public[*].id : aws_subnet.eks_private[*].id
  ci_runner_labels_csv = join(",", var.ci_runner_labels)
  ci_runner_ssm_parameter_names = [
    var.ci_runner_github_app_id_ssm_parameter_name,
    var.ci_runner_github_app_installation_id_ssm_parameter_name,
    var.ci_runner_github_app_private_key_ssm_parameter_name,
  ]
  ci_runner_ssm_parameter_arns = [
    for name in local.ci_runner_ssm_parameter_names :
    "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${trimprefix(name, "/")}"
  ]
}

resource "aws_ssm_parameter" "ci_runner_github_app_id" {
  count = var.create_ci_runner_instance && var.ci_runner_manage_bootstrap_parameters ? 1 : 0

  name      = var.ci_runner_github_app_id_ssm_parameter_name
  type      = "String"
  value     = var.ci_runner_github_app_id_value
  overwrite = true
  tags      = local.ci_runner_tags
}

resource "aws_ssm_parameter" "ci_runner_github_app_installation_id" {
  count = var.create_ci_runner_instance && var.ci_runner_manage_bootstrap_parameters ? 1 : 0

  name      = var.ci_runner_github_app_installation_id_ssm_parameter_name
  type      = "String"
  value     = var.ci_runner_github_app_installation_id_value
  overwrite = true
  tags      = local.ci_runner_tags
}

resource "aws_ssm_parameter" "ci_runner_github_app_private_key" {
  count = var.create_ci_runner_instance && var.ci_runner_manage_bootstrap_parameters ? 1 : 0

  name      = var.ci_runner_github_app_private_key_ssm_parameter_name
  type      = "SecureString"
  value     = var.ci_runner_github_app_private_key_value
  overwrite = true
  tags      = local.ci_runner_tags
}

resource "aws_security_group" "ci_runner" {
  count = var.create_ci_runner_instance && var.create_eks_cluster ? 1 : 0

  name        = "${var.ci_runner_instance_name}-sg"
  description = "GitHub Actions self-hosted CI runner"
  vpc_id      = aws_vpc.eks[0].id

  dynamic "ingress" {
    for_each = length(var.ci_runner_ssh_ingress_cidrs) > 0 ? [1] : []

    content {
      description = "Optional SSH access for troubleshooting"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.ci_runner_ssh_ingress_cidrs
    }
  }

  egress {
    description      = "Allow all outbound traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = local.ci_runner_tags
}

resource "aws_iam_role" "ci_runner" {
  count = var.create_ci_runner_instance && var.create_eks_cluster ? 1 : 0

  name = "${var.ci_runner_instance_name}-role"

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

  tags = local.ci_runner_tags
}

resource "aws_iam_role_policy_attachment" "ci_runner_ssm_core" {
  count = var.create_ci_runner_instance && var.create_eks_cluster ? 1 : 0

  role       = aws_iam_role.ci_runner[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "ci_runner_ssm_parameters" {
  count = var.create_ci_runner_instance && var.create_eks_cluster ? 1 : 0

  statement {
    sid    = "AllowReadRunnerBootstrapParameters"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = local.ci_runner_ssm_parameter_arns
  }
}

resource "aws_iam_role_policy" "ci_runner_ssm_parameters" {
  count = var.create_ci_runner_instance && var.create_eks_cluster ? 1 : 0

  name   = "${var.ci_runner_instance_name}-ssm-parameters"
  role   = aws_iam_role.ci_runner[0].id
  policy = data.aws_iam_policy_document.ci_runner_ssm_parameters[0].json
}

resource "aws_iam_instance_profile" "ci_runner" {
  count = var.create_ci_runner_instance && var.create_eks_cluster ? 1 : 0

  name = "${var.ci_runner_instance_name}-profile"
  role = aws_iam_role.ci_runner[0].name
}

resource "aws_instance" "ci_runner" {
  count = var.create_ci_runner_instance && var.create_eks_cluster ? 1 : 0

  ami                         = data.aws_ami.ci_runner[0].id
  instance_type               = var.ci_runner_instance_type
  subnet_id                   = local.ci_runner_subnet_ids[var.ci_runner_subnet_index]
  vpc_security_group_ids      = [aws_security_group.ci_runner[0].id]
  iam_instance_profile        = aws_iam_instance_profile.ci_runner[0].name
  associate_public_ip_address = var.ci_runner_subnet_type == "public"
  key_name                    = var.ci_runner_ssh_key_name
  monitoring                  = true
  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/templates/github_runner_user_data.sh.tftpl", {
    aws_region                    = var.aws_region
    github_owner                  = var.ci_runner_github_owner
    github_repo                   = var.ci_runner_github_repo
    github_repo_url               = local.ci_runner_repo_url
    runner_labels                 = local.ci_runner_labels_csv
    runner_name_prefix            = var.ci_runner_name_prefix
    github_app_id_parameter_name  = var.ci_runner_github_app_id_ssm_parameter_name
    github_app_installation_param = var.ci_runner_github_app_installation_id_ssm_parameter_name
    github_app_private_key_param  = var.ci_runner_github_app_private_key_ssm_parameter_name
  })

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.ci_runner_root_volume_size
    encrypted   = true

    tags = merge(local.ci_runner_tags, {
      Name = "${var.ci_runner_instance_name}-root"
    })
  }

  tags = local.ci_runner_tags

  lifecycle {
    precondition {
      condition     = length(local.ci_runner_ssm_parameter_names) == 3
      error_message = "Set all three GitHub App SSM parameter names before enabling create_ci_runner_instance."
    }

    precondition {
      condition     = var.ci_runner_subnet_index >= 0 && var.ci_runner_subnet_index < length(local.ci_runner_subnet_ids)
      error_message = "ci_runner_subnet_index must point at an existing subnet in the selected subnet type."
    }

    precondition {
      condition     = length(var.ci_runner_ssh_ingress_cidrs) == 0 || var.ci_runner_ssh_key_name != null
      error_message = "Set ci_runner_ssh_key_name when enabling SSH ingress CIDRs."
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.ci_runner_ssm_core,
    aws_iam_role_policy.ci_runner_ssm_parameters,
    aws_ssm_parameter.ci_runner_github_app_id,
    aws_ssm_parameter.ci_runner_github_app_installation_id,
    aws_ssm_parameter.ci_runner_github_app_private_key,
  ]
}
