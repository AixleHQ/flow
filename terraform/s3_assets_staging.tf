# Staging S3 bucket for object storage.
# Static web assets are served directly by the staging application domain.
# PostgreSQL, Redis, and Temporal all run in-cluster.

locals {
  staging_assets_bucket_name    = "palad-assets-staging"
  staging_assets_bucket_arn     = "arn:aws:s3:::${local.staging_assets_bucket_name}"
  staging_assets_bucket_obj_arn = "${local.staging_assets_bucket_arn}/*"
}

resource "aws_s3_bucket" "assets_staging" {
  bucket        = local.staging_assets_bucket_name
  force_destroy = true

  tags = merge(local.eks_common_tags, {
    Name        = local.staging_assets_bucket_name
    Stack       = "assets"
    Environment = "staging"
  })
}

resource "aws_s3_bucket_public_access_block" "assets_staging" {
  bucket = aws_s3_bucket.assets_staging.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "assets_staging" {
  bucket = aws_s3_bucket.assets_staging.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets_staging" {
  bucket = aws_s3_bucket.assets_staging.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "assets_staging" {
  bucket = aws_s3_bucket.assets_staging.id

  versioning_configuration {
    status = "Suspended"
  }
}

resource "aws_s3_bucket_cors_configuration" "assets_staging" {
  bucket = aws_s3_bucket.assets_staging.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "POST", "PUT", "DELETE", "HEAD"]
    allowed_origins = ["https://staging.aixle.com"]
    expose_headers  = ["ETag", "Location"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "assets_staging" {
  bucket = aws_s3_bucket.assets_staging.id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "assets_staging_bucket_require_tls" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    actions = [
      "s3:*"
    ]
    resources = [
      local.staging_assets_bucket_arn,
      local.staging_assets_bucket_obj_arn
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "assets_staging_require_tls" {
  bucket = aws_s3_bucket.assets_staging.id
  policy = data.aws_iam_policy_document.assets_staging_bucket_require_tls.json
}

# IRSA role for palad-staging workloads to access the staging S3 bucket.
data "aws_iam_policy_document" "eks_assets_staging_irsa_assume_role" {
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
      test = "StringLike"
      values = [
        "system:serviceaccount:palad-staging:palad-web",
        "system:serviceaccount:palad-staging:palad-worker",
      ]
      variable = "${replace(aws_eks_cluster.main[0].identity[0].oidc[0].issuer, "https://", "")}:sub"
    }
  }
}

resource "aws_iam_role" "eks_assets_staging" {
  count = var.create_eks_cluster ? 1 : 0

  name               = "${var.eks_cluster_name}-assets-staging-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assets_staging_irsa_assume_role[0].json

  tags = merge(local.eks_common_tags, {
    Name        = "${var.eks_cluster_name}-assets-staging-role"
    Environment = "staging"
  })
}

data "aws_iam_policy_document" "eks_assets_staging_s3" {
  count = var.create_eks_cluster ? 1 : 0

  statement {
    sid    = "AllowBucketReadMetadata"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads"
    ]
    resources = [
      local.staging_assets_bucket_arn
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
      local.staging_assets_bucket_obj_arn
    ]
  }
}

resource "aws_iam_policy" "eks_assets_staging_s3" {
  count = var.create_eks_cluster ? 1 : 0

  name   = "${var.eks_cluster_name}-assets-staging-s3-policy"
  policy = data.aws_iam_policy_document.eks_assets_staging_s3[0].json

  tags = merge(local.eks_common_tags, {
    Name        = "${var.eks_cluster_name}-assets-staging-s3-policy"
    Environment = "staging"
  })
}

resource "aws_iam_role_policy_attachment" "eks_assets_staging_s3" {
  count = var.create_eks_cluster ? 1 : 0

  role       = aws_iam_role.eks_assets_staging[0].name
  policy_arn = aws_iam_policy.eks_assets_staging_s3[0].arn
}

output "staging_assets_bucket_name" {
  description = "Name of the S3 bucket used by staging asset uploads"
  value       = aws_s3_bucket.assets_staging.id
}

output "staging_assets_bucket_arn" {
  description = "ARN of the S3 bucket used by staging asset uploads"
  value       = local.staging_assets_bucket_arn
}

output "eks_assets_staging_irsa_role_arn" {
  description = "IAM role ARN for IRSA access to the staging assets S3 bucket"
  value       = try(aws_iam_role.eks_assets_staging[0].arn, null)
}
