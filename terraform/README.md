# Terraform Configuration for palad-app

This directory contains the Terraform configuration for managing infrastructure and state storage for the palad-app project.

## Overview

The current configuration sets up:
- **S3 Bucket for State Storage**: An AWS S3 bucket (`palad-tfstate`) to store Terraform state files
- **Versioning Configuration**: Manages bucket versioning for state file safety
- **Private ACL**: Ensures the state bucket is private for security

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
- Download the MinIO provider
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

- **providers.tf** - MinIO provider configuration
- **main.tf** - Resource definitions (S3 bucket, versioning)
- **variables.tf** - Input variables and their defaults
- **outputs.tf** - Output values from Terraform
- **terraform.tfvars.example** - Example configuration (copy to terraform.tfvars)
- **.gitignore** - Files to exclude from version control

## Important Notes

⚠️ **Security**: Never commit `terraform.tfvars` with actual credentials. Use the `.example` template and populate locally.

⚠️ **State Management**: The state file will initially be stored locally. Consider setting up remote state once the S3 bucket is created.

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
