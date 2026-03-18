# Terraform Configuration for palad-app

This directory contains the Terraform configuration for managing AWS infrastructure for the palad-app project.

## Overview

The current configuration sets up:
- **S3 Bucket for State Storage**: An AWS S3 bucket (`palad-tfstate`) to store Terraform state files
- **S3 Bucket for Application Assets** with CORS, encryption, lifecycle, and TLS-only policy
- **CloudFront CDN for Static Rails/Vite Assets** on `static.palad.ai`
- **Route53 Hosted Zone and DNS Records** for `palad.ai`
- **EKS Cluster + Networking** for production workloads
- **Optional EC2 GitHub Actions Self-Hosted Runner** for CI workloads
- **RDS PostgreSQL (Rails app)** for production application database
- **RDS PostgreSQL (Temporal)** for Temporal persistence
- **ElastiCache Redis** for production cache/cable/jobs

## Prerequisites

1. **Terraform** >= 1.0
2. **AWS Account** with appropriate permissions to create S3 buckets
3. **AWS Credentials** (Access Key ID and Secret Access Key)
4. **AWS Terraform Provider** (automatically managed via `terraform init`)

## Setup Instructions

### 1. Set AWS Credentials via Environment Variables

The AWS provider uses environment variables for authentication:

```bash
export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
export AWS_REGION="us-east-1"
```

### 2. Configure Terraform Variables

Copy and customize the example configuration:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` to customize your bucket name and region if needed:

```hcl
aws_region          = "us-east-1"
tfstate_bucket_name = "palad-tfstate-prod"
```

### 3. Initialize Terraform

```bash
terraform init
```

This will:
- Download the Terraform providers
- Initialize the local workspace
- Create a `.terraform` directory

### 4. Review and Apply Changes

```bash
terraform plan    # Review what will be created
terraform apply   # Create the resources
```

### 5. Verify Resources

```bash
terraform output  # Display output values
```

## File Structure

- **providers.tf** - Terraform providers (AWS, TLS)
- **main.tf** - S3 tfstate resources
- **s3_assets.tf** - S3 assets bucket and EKS IRSA role/policy for app uploads
- **cloudfront_static_assets.tf** - CloudFront, ACM, and Route53 alias for static asset delivery
- **eks.tf** - EKS cluster and VPC resources
- **github_runner.tf** - Optional EC2 GitHub Actions runner resources
- **rds.tf** - Managed RDS PostgreSQL resources
- **rds_temporal.tf** - Dedicated managed RDS PostgreSQL resources for Temporal
- **redis.tf** - Managed ElastiCache Redis resources
- **variables.tf** - Input variables and their defaults
- **outputs.tf** - Output values from Terraform
- **terraform.tfvars.example** - Example configuration (copy to terraform.tfvars)
- **.gitignore** - Files to exclude from version control

## Important Notes

⚠️ **Security**: Never commit `terraform.tfvars` with actual credentials. Use the `.example` template and populate locally.

⚠️ **Production DB Passwords**:
- `rds_master_password` is required for Rails RDS.
- `temporal_rds_master_password` is required for Temporal RDS when enabled.

⚠️ **GitHub Runner Bootstrap**:
- The EC2 runner path creates three SSM parameters for the GitHub App bootstrap values:
  - app ID
  - installation ID
  - private key PEM as `SecureString`
- The GitHub App must have repository `Administration: Read and write` on the target repo so the instance can mint runner registration tokens at boot.
- Those secret values will exist in Terraform state because Terraform is managing the SSM parameters directly.

⚠️ **Kubernetes Sync**: After `terraform apply`, update production Kubernetes values:
- `kube/prod/07-app-config.yaml`:
  - `DB_HOST` from `terraform output rds_endpoint`
  - `TEMPORAL_DB_HOST` from `terraform output temporal_rds_endpoint`
  - `REDIS_URL` from `terraform output redis_url_database_1`
  - `AWS_S3_BUCKET` from `terraform output assets_bucket_name`
  - `AWS_DEFAULT_REGION` / `AWS_REGION` from `terraform output assets_bucket_region`
  - `ASSET_HOST` from `terraform output cloudfront_static_assets_url` (for example `https://static.palad.ai`)
  - `K8S_EKS_VPC_CIDR` should match `eks_vpc_cidr` (runtime network policy blocks private/VPC egress while allowing public internet)
- `kube/prod/06-rbac-runtime.yaml`:
  - `eks.amazonaws.com/role-arn` for `palad-web` and `palad-worker` from `terraform output eks_assets_irsa_role_arn`
- `kube/prod/14-cluster-autoscaler.yaml`:
  - `eks.amazonaws.com/role-arn` for `cluster-autoscaler` from `terraform output eks_cluster_autoscaler_irsa_role_arn`
  - ensure `--node-group-auto-discovery` tag key includes your `eks_cluster_name`
- `kube/prod/secrets/07-app-secrets.yaml`:
  - `DB_PASSWORD` must match `rds_master_password`
  - `TEMPORAL_DB_PASSWORD` must match `temporal_rds_master_password`

## Useful Commands

```bash
terraform init      # Initialize Terraform
terraform plan      # Preview changes
terraform apply     # Apply changes
terraform destroy   # Remove resources
terraform validate  # Check syntax
terraform fmt       # Format code
```

## CI/CD Integration

When running in CI/CD pipelines, use environment variables for AWS credentials:

```bash
export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
export AWS_REGION="us-east-1"
```

Or use other AWS credential providers (IAM roles, credentials file, SSO, etc.) that the AWS provider supports.

For Terraform variables, you can use environment variables with `TF_VAR_` prefix:

```bash
export TF_VAR_tfstate_bucket_name="palad-tfstate-prod"
```

## References

- [AWS Terraform Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS S3 Bucket Resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket)
- [Terraform Documentation](https://www.terraform.io/docs)
