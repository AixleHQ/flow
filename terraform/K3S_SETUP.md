# k3s and EC2 Setup Guide

## Overview

The Terraform configuration now includes:
- **VPC** and **Subnet** for isolated networking
- **Security Group** with ports for SSH, HTTP, HTTPS, and Kubernetes API
- **EC2 Instance** with latest Ubuntu 24.04 LTS AMI
- **Elastic IP** for stable public IP
- **Automatic k3s installation** via user data script

## Instance Configuration

### Recommended Instance Types

| Type | vCPU | RAM | Cost | Suitable For |
|------|------|-----|------|--------------|
| t3.micro | 1 | 1 GB | $0.01/hr | Testing only |
| **t3.small** | 2 | 2 GB | $0.02/hr | Development (minimum) |
| t3.medium | 2 | 4 GB | $0.04/hr | Production (recommended) |
| t3.large | 2 | 8 GB | $0.08/hr | High-load production |

**For your setup** (Rails app + PostgreSQL + Redis + Temporal), **t3.small is the minimum**. **t3.medium is recommended** for better performance.

## Deployment Steps

### 1. Set Variables (if needed)

In `terraform.tfvars`, you can customize:

```hcl
aws_region          = "us-east-1"
tfstate_bucket_name = "palad-tfstate-prod"
k3s_instance_type   = "t3.small"  # Change to t3.medium if needed
```

### 2. Deploy the Infrastructure

```bash
cd terraform
terraform plan      # Review changes
terraform apply     # Deploy EC2 and network resources
```

### 3. Wait for k3s Installation

The instance will automatically install k3s on startup (takes ~2-3 minutes). Monitor progress:

```bash
terraform output k3s_instance_public_ip  # Get the IP
ssh -i <your-key-pair> ubuntu@<public-ip>
sudo systemctl status k3s                # Check k3s status
```

### 4. Get the kubeconfig

Option A: From the instance

```bash
ssh -i <your-key-pair> ubuntu@<public-ip>
sudo cat /etc/rancher/k3s/k3s.yaml
```

Option B: Using terraform outputs and scp

```bash
# Get outputs
terraform output -json

# Copy kubeconfig
scp -i <your-key-pair> ubuntu@$(terraform output -raw k3s_instance_public_ip):/etc/rancher/k3s/k3s.yaml ./kubeconfig.yaml

# Edit the kubeconfig to replace 'localhost' with the public IP
sed -i 's/127.0.0.1/'"$(terraform output -raw k3s_instance_public_ip)"'/g' kubeconfig.yaml
```

### 5. Deploy Your Application

Once you have kubeconfig:

```bash
export KUBECONFIG=./kubeconfig.yaml

# Apply your Kubernetes manifests
kubectl create namespace palad
kubectl apply -f ../kube/common/
kubectl apply -f ../kube/prod/
```

## SSH Access

Use the output from Terraform:

```bash
# Get the command
terraform output k3s_ssh_command

# Or manually
ssh -i <your-key-pair> ubuntu@$(terraform output -raw k3s_instance_public_ip)
```

## Useful Commands

```bash
# Check instance status
terraform output k3s_instance_id
terraform output k3s_instance_public_ip

# SSH into instance
ssh -i your-key.pem ubuntu@$(terraform output -raw k3s_instance_public_ip)

# Check k3s status (once SSH'd in)
sudo systemctl status k3s
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A

# View k3s logs
sudo journalctl -xe -u k3s
```

## Security Considerations

⚠️ Current security group allows SSH (22) from anywhere (0.0.0.0/0). For production, restrict this:

```hcl
# In ec2.tf, modify the SSH ingress rule
ingress {
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["YOUR_IP/32"]  # Replace with your IP
  description = "SSH access from specific IP"
}
```

## Cleanup

Remove all resources:

```bash
terraform destroy
```

## Troubleshooting

### Instance not ready
- Wait 2-3 minutes for user data script to complete
- Check CloudWatch logs in AWS console

### Can't connect via kubectl
- Ensure kubeconfig has the correct public IP (not localhost)
- Check security group allows port 6443

### k3s service not running
```bash
ssh -i your-key.pem ubuntu@<public-ip>
sudo systemctl restart k3s
sudo systemctl status k3s
```

### Check k3s installation logs
```bash
ssh -i your-key.pem ubuntu@<public-ip>
sudo journalctl -xe -u k3s | tail -100
```

## Next Steps

1. **Create SSH key pair** in AWS EC2 console (if you don't have one)
2. **Deploy infrastructure** with `terraform apply`
3. **Get kubeconfig** and test connection
4. **Deploy Kubernetes manifests** from `kube/common/` and `kube/dev/` or `kube/prod/` depending on environment

## References

- [k3s Documentation](https://docs.k3s.io)
- [AWS EC2 Instance Types](https://aws.amazon.com/ec2/instance-types/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
