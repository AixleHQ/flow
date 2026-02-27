variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "tfstate_bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  type        = string
  default     = "palad-tfstate"
}

variable "k3s_instance_type" {
  description = "EC2 instance type for k3s cluster"
  type        = string
  default     = "t3.small"

  validation {
    condition     = contains(["t3.micro", "t3.small", "t3.medium", "t3.large"], var.k3s_instance_type)
    error_message = "Instance type must be one of: t3.micro, t3.small, t3.medium, t3.large."
  }
}

variable "create_k3s_instance" {
  description = "Whether to create the k3s EC2 instance and dependent DNS records"
  type        = bool
  default     = false
}
