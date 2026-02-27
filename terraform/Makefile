# Terraform/EKS helper targets
.PHONY: terraform-help terraform-plan terraform-apply eks-init-kubeconfig eks-kubeconfig-path eks-test eks-contexts vault-bash

EKS_CLUSTER_NAME ?= palad-eks
EKS_CONTEXT_NAME ?= palad-prod
AWS_REGION ?= us-east-1
TF_ARGS ?=

terraform-help:
	@echo "Terraform/EKS commands:"
	@echo "  make terraform-plan         - Run terraform plan (use TF_ARGS='...')"
	@echo "  make terraform-apply        - Run terraform apply (use TF_ARGS='...')"
	@echo "  make eks-init-kubeconfig    - Merge EKS access into ~/.kube/config with context alias $(EKS_CONTEXT_NAME)"
	@echo "  make eks-kubeconfig-path    - Show default kubeconfig path and EKS context alias"
	@echo "  make eks-test               - Test kubectl connection to EKS cluster using context alias $(EKS_CONTEXT_NAME)"
	@echo "  make eks-contexts           - Show kubectl contexts (including $(EKS_CONTEXT_NAME) if present)"
	@echo "  make vault-bash             - Open a bash shell with AWS Vault credentials for Terraform operations"

terraform-plan:
	cd terraform && terraform plan $(TF_ARGS)

terraform-apply:
	cd terraform && terraform apply $(TF_ARGS)

# Initialize kubeconfig from EKS cluster
eks-init-kubeconfig:
	@echo "Updating default kubeconfig (~/.kube/config) for EKS cluster $(EKS_CLUSTER_NAME) in $(AWS_REGION) with context alias $(EKS_CONTEXT_NAME)..."; \
	aws eks update-kubeconfig --name "$(EKS_CLUSTER_NAME)" --region "$(AWS_REGION)" --alias "$(EKS_CONTEXT_NAME)"; \
	echo "✓ EKS context added to ~/.kube/config as: $(EKS_CONTEXT_NAME)"

eks-kubeconfig-path:
	@echo "Default kubeconfig path: ~/.kube/config"
	@echo "EKS context alias: $(EKS_CONTEXT_NAME)"

# Test kubectl connection to EKS cluster
eks-test:
	@if ! kubectl config get-contexts "$(EKS_CONTEXT_NAME)" > /dev/null 2>&1; then \
		echo "Error: Context $(EKS_CONTEXT_NAME) not found. Run 'make eks-init-kubeconfig' first."; \
		exit 1; \
	fi
	@echo "Testing kubectl connection to EKS cluster using context $(EKS_CONTEXT_NAME)..."
	@kubectl --context "$(EKS_CONTEXT_NAME)" cluster-info
	@echo ""
	@echo "✓ Connection successful!"

# Show kubectl contexts for EKS kubeconfig
eks-contexts:
	@kubectl config get-contexts

# Open a bash shell with AWS Vault credentials for Terraform operations
vault-bash:
	aws-vault exec terraform@palad -- bash
