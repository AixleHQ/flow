# Kubernetes targets
.PHONY: kube-help kube-status kube-setup kube-setup-prod kube-apply kube-apply-dev kube-apply-prod kube-secrets-apply kube-secret-set kube-web-rollout kube-mount-dev kube-rm kube-rm-prod kube-arc-install-controller kube-arc-apply-deploy-rbac kube-arc-install-runner-set kube-arc-install

KUBE_COMMON_DIR = ./kube/common
KUBE_DEV_DIR = ./kube/dev
KUBE_PROD_DIR = ./kube/prod
KUBE_SECRETS_DIR = ./kube/secrets
TRAEFIK_CRD_URL = https://raw.githubusercontent.com/traefik/traefik/v3.3/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml
KUBE_CONTEXT ?=
KUBE_NAMESPACE ?= palad
SECRET_NAMESPACE ?= $(KUBE_NAMESPACE)
SECRET_NAME ?=
KUBE_EDITOR ?= vim
KUBECTL = kubectl $(if $(KUBE_CONTEXT),--context $(KUBE_CONTEXT))
ARC_CONTROLLER_INSTALLATION_NAME ?= arc
ARC_CONTROLLER_NAMESPACE ?= arc-system
ARC_RUNNER_INSTALLATION_NAME ?= palad-deploy-runner
ARC_RUNNER_NAMESPACE ?= arc-runners
ARC_RUNNER_VALUES_FILE ?= ./kube/arc/values-runner-scale-set.yaml

kube-help:
	@echo "Kubernetes commands:"
	@echo "  make kube-status            - Show cluster and namespace health (use KUBE_CONTEXT=... KUBE_NAMESPACE=...)"
	@echo "  make kube-setup             - Build images + apply common+secrets+dev manifests + run db-prepare"
	@echo "  make kube-setup-prod        - Install Traefik CRDs + apply common+secrets+prod manifests"
	@echo "  make kube-apply             - Apply common + dev manifests (secrets are not touched)"
	@echo "  make kube-apply-dev         - Apply common + dev manifests + WEB_HOST_PATH mount for web"
	@echo "  make kube-apply-prod        - Apply common + prod manifests (secrets are not touched)"
	@echo "  make kube-secrets-apply     - Apply secret manifests from kube/secrets explicitly"
	@echo "  make kube-secret-set        - Open an existing secret in vim and save back (SECRET_NAME=... [SECRET_NAMESPACE=...])"
	@echo "  make kube-web-rollout       - Rollout restart web, worker-ruby, and mcp deployments"
	@echo "  make kube-arc-install-controller - Install/upgrade ARC controller chart"
	@echo "  make kube-arc-apply-deploy-rbac  - Apply deploy-runner ServiceAccount and rollout RBAC"
	@echo "  make kube-arc-install-runner-set - Install/upgrade ARC runner scale set chart"
	@echo "  make kube-arc-install            - Install ARC controller + deploy RBAC + runner scale set"
	@echo "  make kube-rm                - Delete dev + common manifests (secrets are not touched)"
	@echo "  make kube-rm-prod           - Delete prod + common manifests (secrets are not touched)"

kube-status:
	@echo "=== Kubernetes Status ==="
	@echo "Context: $$($(KUBECTL) config current-context)"
	@echo "Namespace: $(KUBE_NAMESPACE)"
	@echo ""
	@echo "--- Cluster Info ---"
	@$(KUBECTL) cluster-info
	@echo ""
	@echo "--- Nodes ---"
	@$(KUBECTL) get nodes -o wide
	@echo ""
	@echo "--- Namespaces ---"
	@$(KUBECTL) get ns
	@echo ""
	@echo "--- Workloads ($(KUBE_NAMESPACE)) ---"
	@$(KUBECTL) get pods -n $(KUBE_NAMESPACE) -o wide
	@$(KUBECTL) get deploy,statefulset,daemonset -n $(KUBE_NAMESPACE)
	@echo ""
	@echo "--- Services/Endpoints ($(KUBE_NAMESPACE)) ---"
	@$(KUBECTL) get svc -n $(KUBE_NAMESPACE)
	@$(KUBECTL) get endpoints -n $(KUBE_NAMESPACE)
	@echo ""
	@echo "--- Ingress ---"
	@$(KUBECTL) get ingress -A 2>/dev/null || true
	@$(KUBECTL) get ingressroutes.traefik.io -A 2>/dev/null || true
	@echo ""
	@echo "--- Recent Events ($(KUBE_NAMESPACE)) ---"
	@$(KUBECTL) get events -n $(KUBE_NAMESPACE) --sort-by=.lastTimestamp | tail -n 40

# Full Kubernetes setup: CRDs, manifests, wait for pods, migrate and seed
kube-setup:
	@make build-web
	@make build-otlp-ingest
	@make build-agents
	$(KUBECTL) apply -f $(TRAEFIK_CRD_URL)
	$(KUBECTL) apply -f $(KUBE_COMMON_DIR)
	@make kube-arc-install
	$(KUBECTL) apply -f $(KUBE_SECRETS_DIR)
	$(KUBECTL) apply -f $(KUBE_DEV_DIR)
	$(KUBECTL) wait --for=condition=ready pod -l app=db -n palad --timeout=120s
	$(KUBECTL) wait --for=condition=ready pod -l app=web -n palad --timeout=120s
	$(KUBECTL) exec -n palad deployment/web -- make db-prepare
	@make kube-mount-dev

# Production Kubernetes setup: CRDs + secrets + production manifests
kube-setup-prod:
	$(KUBECTL) apply -f $(TRAEFIK_CRD_URL)
	$(KUBECTL) apply -f $(KUBE_COMMON_DIR)/00-namespace.yaml
	$(KUBECTL) apply -f $(KUBE_SECRETS_DIR)
	@make kube-apply-prod

kube-apply:
	$(KUBECTL) apply -f $(KUBE_COMMON_DIR)
	$(KUBECTL) apply -f $(KUBE_DEV_DIR)

# Apply Kubernetes manifests and mount local source for development
kube-apply-dev: kube-apply kube-mount-dev

# Apply production Kubernetes manifests
kube-apply-prod:
	$(KUBECTL) apply -f $(KUBE_COMMON_DIR)
	$(KUBECTL) apply -f $(KUBE_PROD_DIR)

# Apply secret manifests only when explicitly requested
kube-secrets-apply:
	$(KUBECTL) apply -f $(KUBE_SECRETS_DIR)

# Restart web-related deployments to pick up new config/secrets
kube-web-rollout:
	$(KUBECTL) rollout restart deployment/web deployment/worker-ruby deployment/mcp -n $(KUBE_NAMESPACE)

# Install/upgrade Actions Runner Controller (ARC) controller chart.
kube-arc-install-controller:
	helm upgrade --install "$(ARC_CONTROLLER_INSTALLATION_NAME)" \
		oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
		--namespace "$(ARC_CONTROLLER_NAMESPACE)" \
		--create-namespace

# Apply runner service account in arc-runners and rollout RBAC in palad namespace.
kube-arc-apply-deploy-rbac:
	$(KUBECTL) apply -f ./kube/arc/01-deploy-runner-rbac.yaml

# Install/upgrade ARC runner scale set for deploy jobs.
kube-arc-install-runner-set:
	helm upgrade --install "$(ARC_RUNNER_INSTALLATION_NAME)" \
		oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
		--namespace "$(ARC_RUNNER_NAMESPACE)" \
		--create-namespace \
		--set "controllerServiceAccount.namespace=$(ARC_CONTROLLER_NAMESPACE)" \
		--set "controllerServiceAccount.name=$(ARC_CONTROLLER_INSTALLATION_NAME)-gha-rs-controller" \
		-f "$(ARC_RUNNER_VALUES_FILE)"

# One-shot ARC setup for deploy runner scale set.
kube-arc-install: kube-arc-install-controller kube-arc-apply-deploy-rbac kube-arc-install-runner-set

# Edit an existing secret interactively and save changes back to the cluster
kube-secret-set:
	@if [ -z "$(SECRET_NAME)" ]; then \
		echo "SECRET_NAME is not set. Available secrets in namespace $(SECRET_NAMESPACE):"; \
		$(KUBECTL) get secrets -n "$(SECRET_NAMESPACE)" || true; \
		echo "Usage: make kube-secret-set SECRET_NAME=<secret-name> [SECRET_NAMESPACE=palad] [KUBE_EDITOR=vim]"; \
		exit 1; \
	fi
	@KUBE_EDITOR="$(KUBE_EDITOR)" $(KUBECTL) edit secret "$(SECRET_NAME)" -n "$(SECRET_NAMESPACE)"

# Default to current directory's web folder if not provided
WEB_HOST_PATH ?= $(shell pwd)

# Apply Kubernetes manifests with a dev hostPath for the web container
kube-mount-dev:
	$(KUBECTL) patch deployment web -n palad --type='strategic' -p "{\"spec\":{\"template\":{\"spec\":{\"volumes\":[{\"name\":\"web-source\",\"hostPath\":{\"path\":\"$(WEB_HOST_PATH)\",\"type\":\"Directory\"}}],\"containers\":[{\"name\":\"web\",\"volumeMounts\":[{\"name\":\"web-source\",\"mountPath\":\"/app\"}]}]}}}}"
	$(KUBECTL) rollout restart deployment/web -n palad
	$(KUBECTL) patch deployment worker-ruby -n palad --type='strategic' -p "{\"spec\":{\"template\":{\"spec\":{\"volumes\":[{\"name\":\"web-source\",\"hostPath\":{\"path\":\"$(WEB_HOST_PATH)\",\"type\":\"Directory\"}}],\"containers\":[{\"name\":\"worker-ruby\",\"volumeMounts\":[{\"name\":\"web-source\",\"mountPath\":\"/app\"}]}]}}}}"
	$(KUBECTL) rollout restart deployment/worker-ruby -n palad

# Remove Kubernetes manifests
kube-rm:
	$(KUBECTL) delete -f $(KUBE_DEV_DIR)
	$(KUBECTL) delete -f $(KUBE_COMMON_DIR)

# Remove production Kubernetes manifests
kube-rm-prod:
	$(KUBECTL) delete -f $(KUBE_PROD_DIR)
	$(KUBECTL) delete -f $(KUBE_COMMON_DIR)
