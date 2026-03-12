terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Credentials are provided via AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY env vars
}

# CloudFront ACM certificates must be created in us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
