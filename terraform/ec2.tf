# Security Group for k3s instance
resource "aws_security_group" "k3s_sg" {
  name        = "palad-k3s-sg"
  description = "Security group for k3s cluster"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["212.58.121.200/32"]
    description = "SSH access from 212.58.121.200"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["212.58.121.200/32"]
    description = "HTTP access from 212.58.121.200"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["212.58.121.200/32"]
    description = "HTTPS access from 212.58.121.200"
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["212.58.121.200/32"]
    description = "Kubernetes API server from 212.58.121.200"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "palad-k3s-sg"
  }
}

# VPC for k3s instance
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "palad-vpc"
  }
}

# Subnet for k3s instance
resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "palad-subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "palad-igw"
  }
}

# Route Table
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block      = "0.0.0.0/0"
    gateway_id      = aws_internet_gateway.main.id
  }

  tags = {
    Name = "palad-rt"
  }
}

# Route Table Association
resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Get the latest Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# k3s installation script
locals {
  k3s_install_script = <<-EOF
#!/bin/bash
set -e

# Update system
apt-get update
apt-get install -y \
  curl \
  wget \
  git \
  htop \
  net-tools \
  vim \
  unzip

# Install k3s
curl -sfL https://get.k3s.io | sh -

# Wait for k3s to be ready
sleep 10
until kubectl get serviceaccount default > /dev/null 2>&1; do
  echo "Waiting for k3s to be ready..."
  sleep 5
done

# Create palad namespace
kubectl create namespace palad || true

# Output kubeconfig for reference
echo "=== k3s installed successfully ==="
echo "Kubeconfig location: /etc/rancher/k3s/k3s.yaml"
EOF
}

# EC2 Instance for k3s
resource "aws_instance" "k3s" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.k3s_instance_type
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.k3s_sg.id]
  
  # Use instance store or EBS
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
  }

  user_data = base64encode(local.k3s_install_script)

  # Add tags
  tags = {
    Name = "palad-k3s"
  }

  monitoring = true

  depends_on = [aws_internet_gateway.main]
}

# Elastic IP for stable public IP
resource "aws_eip" "k3s" {
  instance = aws_instance.k3s.id
  domain   = "vpc"

  tags = {
    Name = "palad-k3s-eip"
  }

  depends_on = [aws_internet_gateway.main]
}
