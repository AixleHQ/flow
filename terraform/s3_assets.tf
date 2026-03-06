locals {
  assets_bucket_arn     = "arn:aws:s3:::${var.assets_bucket_name}"
  assets_bucket_obj_arn = "${local.assets_bucket_arn}/*"
}

resource "aws_s3_bucket" "assets" {
  count = var.create_assets_bucket ? 1 : 0

  bucket        = var.assets_bucket_name
  force_destroy = var.assets_bucket_force_destroy

  tags = merge(local.eks_common_tags, {
    Name  = var.assets_bucket_name
    Stack = "assets"
  })
}

resource "aws_s3_bucket_public_access_block" "assets" {
  count = var.create_assets_bucket ? 1 : 0

  bucket = aws_s3_bucket.assets[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "assets" {
  count = var.create_assets_bucket ? 1 : 0

  bucket = aws_s3_bucket.assets[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  count = var.create_assets_bucket ? 1 : 0

  bucket = aws_s3_bucket.assets[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "assets" {
  count = var.create_assets_bucket ? 1 : 0

  bucket = aws_s3_bucket.assets[0].id

  versioning_configuration {
    status = var.assets_bucket_versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_cors_configuration" "assets" {
  count = var.create_assets_bucket ? 1 : 0

  bucket = aws_s3_bucket.assets[0].id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "POST", "PUT", "DELETE", "HEAD"]
    allowed_origins = var.assets_bucket_cors_allowed_origins
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "assets" {
  count = var.create_assets_bucket ? 1 : 0

  bucket = aws_s3_bucket.assets[0].id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "assets_bucket_require_tls" {
  count = var.create_assets_bucket ? 1 : 0

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    actions = [
      "s3:*"
    ]
    resources = [
      local.assets_bucket_arn,
      local.assets_bucket_obj_arn
    ]

    principals {
      type = "*"
      identifiers = [
        "*"
      ]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values = [
        "false"
      ]
    }
  }
}

resource "aws_s3_bucket_policy" "assets_require_tls" {
  count = var.create_assets_bucket ? 1 : 0

  bucket = aws_s3_bucket.assets[0].id
  policy = data.aws_iam_policy_document.assets_bucket_require_tls[0].json
}

data "aws_iam_policy_document" "eks_assets_irsa_assume_role" {
  count = var.create_eks_cluster && var.create_assets_irsa ? 1 : 0

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
      test = "StringLike"
      values = [
        for service_account in var.assets_irsa_service_account_names : "system:serviceaccount:${var.assets_irsa_namespace}:${service_account}"
      ]
      variable = "${replace(aws_eks_cluster.main[0].identity[0].oidc[0].issuer, "https://", "")}:sub"
    }
  }
}

resource "aws_iam_role" "eks_assets" {
  count = var.create_eks_cluster && var.create_assets_irsa ? 1 : 0

  name               = "${var.eks_cluster_name}-assets-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assets_irsa_assume_role[0].json

  tags = merge(local.eks_common_tags, {
    Name = "${var.eks_cluster_name}-assets-role"
  })
}

data "aws_iam_policy_document" "eks_assets_s3" {
  count = var.create_eks_cluster && var.create_assets_irsa ? 1 : 0

  statement {
    sid    = "AllowBucketReadMetadata"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads"
    ]
    resources = [
      local.assets_bucket_arn
    ]
  }

  statement {
    sid    = "AllowObjectReadWriteDelete"
    effect = "Allow"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:ListMultipartUploadParts",
      "s3:PutObject"
    ]
    resources = [
      local.assets_bucket_obj_arn
    ]
  }
}

resource "aws_iam_policy" "eks_assets_s3" {
  count = var.create_eks_cluster && var.create_assets_irsa ? 1 : 0

  name   = "${var.eks_cluster_name}-assets-s3-policy"
  policy = data.aws_iam_policy_document.eks_assets_s3[0].json

  tags = merge(local.eks_common_tags, {
    Name = "${var.eks_cluster_name}-assets-s3-policy"
  })
}

resource "aws_iam_role_policy_attachment" "eks_assets_s3" {
  count = var.create_eks_cluster && var.create_assets_irsa ? 1 : 0

  role       = aws_iam_role.eks_assets[0].name
  policy_arn = aws_iam_policy.eks_assets_s3[0].arn
}
