# Terraform/K3S helper targets
.PHONY: terraform-help k3s-init-kubeconfig k3s-kubeconfig-path k3s-test k3s-contexts

KUBECONFIG_LOCAL = ~/.kube/config-palad-k3s
KUBECONFIG_TEMP = /tmp/kubeconfig-palad-k3s

terraform-help:
	@echo "Terraform/K3S commands:"
	@echo "  make k3s-init-kubeconfig    - Fetch kubeconfig from k3s instance and save locally"
	@echo "  make k3s-kubeconfig-path    - Show kubeconfig location and usage"
	@echo "  make k3s-test               - Test kubectl connection to k3s cluster"
	@echo "  make k3s-contexts           - Show kubectl contexts for k3s kubeconfig"

# Initialize kubeconfig from k3s instance
k3s-init-kubeconfig:
	@K3S_INSTANCE_ID=$$(cd terraform && terraform output -raw k3s_instance_id 2>/dev/null); \
	K3S_INSTANCE_IP=$$(cd terraform && terraform output -raw k3s_instance_public_ip 2>/dev/null); \
	if [ -z "$$K3S_INSTANCE_ID" ]; then \
		echo "Error: Could not get instance ID from Terraform. Make sure k3s instance is deployed."; \
		exit 1; \
	fi; \
	echo "Fetching kubeconfig from k3s instance ($$K3S_INSTANCE_ID at $$K3S_INSTANCE_IP)..."; \
	echo "Sending command via AWS SSM..."; \
	COMMAND_ID=$$(aws ssm send-command \
		--instance-ids "$$K3S_INSTANCE_ID" \
		--document-name "AWS-RunShellScript" \
		--parameters 'commands=["sudo cat /etc/rancher/k3s/k3s.yaml"]' \
		--query "Command.CommandId" \
		--output text 2>&1); \
	if echo "$$COMMAND_ID" | grep -q "error\|Error"; then \
		echo "✗ SSM not available. Please use the manual method:"; \
		echo ""; \
		echo "1. SSH into the instance:"; \
		echo "   ssh -i <your-key.pem> ubuntu@$$K3S_INSTANCE_IP"; \
		echo ""; \
		echo "2. Get the kubeconfig:"; \
		echo "   sudo cat /etc/rancher/k3s/k3s.yaml"; \
		echo ""; \
		echo "3. Copy the output and save it to $(KUBECONFIG_LOCAL)"; \
		echo ""; \
		echo "4. Replace 127.0.0.1 with $$K3S_INSTANCE_IP in the file"; \
		exit 1; \
	fi; \
	echo "Waiting for command to complete..."; \
	sleep 3; \
	aws ssm get-command-invocation \
		--command-id "$$COMMAND_ID" \
		--instance-id "$$K3S_INSTANCE_ID" \
		--query "StandardOutputContent" \
		--output text > $(KUBECONFIG_TEMP); \
	if [ ! -s $(KUBECONFIG_TEMP) ]; then \
		echo "✗ Could not retrieve kubeconfig. Trying alternative method..."; \
		echo "Please manually copy the kubeconfig using:"; \
		echo "  ssh -i <your-key.pem> ubuntu@$$K3S_INSTANCE_IP 'sudo cat /etc/rancher/k3s/k3s.yaml'"; \
		rm -f $(KUBECONFIG_TEMP); \
		exit 1; \
	fi; \
	echo "Updating kubeconfig to use IP address ($$K3S_INSTANCE_IP)..."; \
	sed "s/127\.0\.0\.1/$$K3S_INSTANCE_IP/g; s/localhost/$$K3S_INSTANCE_IP/g" $(KUBECONFIG_TEMP) > $(KUBECONFIG_LOCAL); \
	chmod 600 $(KUBECONFIG_LOCAL); \
	rm -f $(KUBECONFIG_TEMP); \
	echo "✓ Kubeconfig saved to: $(KUBECONFIG_LOCAL)"; \
	echo ""; \
	echo "To use this kubeconfig, run:"; \
	echo "  export KUBECONFIG=$(KUBECONFIG_LOCAL)"; \
	echo ""; \
	echo "Or merge it with your default kubeconfig:"; \
	echo "  KUBECONFIG=$(KUBECONFIG_LOCAL):~/.kube/config kubectl config view --flatten > ~/.kube/config.merged && mv ~/.kube/config.merged ~/.kube/config"

# Show kubeconfig path for current session
k3s-kubeconfig-path:
	@echo "Kubeconfig location: $(KUBECONFIG_LOCAL)"
	@if [ -f $(KUBECONFIG_LOCAL) ]; then \
		echo "✓ Kubeconfig exists"; \
		echo ""; \
		echo "To use it, run:"; \
		echo "  export KUBECONFIG=$(KUBECONFIG_LOCAL)"; \
	else \
		echo "✗ Kubeconfig not found. Run 'make k3s-init-kubeconfig' first"; \
	fi

# Test kubectl connection to k3s cluster
k3s-test:
	@if [ -z "$${KUBECONFIG}" ] && [ ! -f $(KUBECONFIG_LOCAL) ]; then \
		echo "Error: KUBECONFIG not set. Run 'make k3s-init-kubeconfig' first"; \
		exit 1; \
	fi
	@echo "Testing kubectl connection to k3s cluster..."
	@KUBECONFIG=$${KUBECONFIG:=$(KUBECONFIG_LOCAL)} kubectl cluster-info
	@echo ""
	@echo "✓ Connection successful!"

# Show kubectl contexts
k3s-contexts:
	@if [ -z "$${KUBECONFIG}" ] && [ ! -f $(KUBECONFIG_LOCAL) ]; then \
		echo "Error: KUBECONFIG not set. Run 'make k3s-init-kubeconfig' first"; \
		exit 1; \
	fi
	@KUBECONFIG=$${KUBECONFIG:=$(KUBECONFIG_LOCAL)} kubectl config get-contexts
