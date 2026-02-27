# Kubernetes targets
.PHONY: kube-help kube-status kube-setup kube-setup-prod kube-apply kube-apply-dev kube-apply-prod kube-prod-ghcr-secret kube-mount-dev kube-rm kube-rm-prod

KUBE_COMMON_DIR = ./kube/common
KUBE_DEV_DIR = ./kube/dev
KUBE_PROD_DIR = ./kube/prod
TRAEFIK_CRD_URL = https://raw.githubusercontent.com/traefik/traefik/v3.3/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml
KUBE_CONTEXT ?=
KUBE_NAMESPACE ?= palad
KUBECTL = kubectl $(if $(KUBE_CONTEXT),--context $(KUBE_CONTEXT))

kube-help:
	@echo "Kubernetes commands:"
	@echo "  make kube-status            - Show cluster and namespace health (use KUBE_CONTEXT=... KUBE_NAMESPACE=...)"
	@echo "  make kube-setup             - Build images + apply common+dev manifests + run db-prepare"
	@echo "  make kube-setup-prod        - Install Traefik CRDs + GHCR secret + apply common+prod manifests"
	@echo "  make kube-apply             - Apply common + dev manifests"
	@echo "  make kube-apply-dev         - Apply common + dev manifests + WEB_HOST_PATH mount for web"
	@echo "  make kube-apply-prod        - Apply common + prod manifests"
	@echo "  make kube-prod-ghcr-secret  - Create/update GHCR pull secret in palad namespace"
	@echo "  make kube-rm                - Delete dev + common manifests"
	@echo "  make kube-rm-prod           - Delete prod + common manifests"

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
	kubectl apply -f $(TRAEFIK_CRD_URL)
	kubectl apply -f $(KUBE_COMMON_DIR)
	kubectl apply -f $(KUBE_DEV_DIR)
	kubectl wait --for=condition=ready pod -l app=db -n palad --timeout=120s
	kubectl wait --for=condition=ready pod -l app=web -n palad --timeout=120s
	kubectl exec -n palad deployment/web -- make db-prepare
	@make kube-mount-dev

# Production Kubernetes setup: CRDs + pull secret + production manifests
kube-setup-prod:
	kubectl apply -f $(TRAEFIK_CRD_URL)
	@make kube-prod-ghcr-secret GHCR_USERNAME="$(GHCR_USERNAME)" GHCR_TOKEN="$(GHCR_TOKEN)"
	@make kube-apply-prod

kube-apply:
	kubectl apply -f $(KUBE_COMMON_DIR)
	kubectl apply -f $(KUBE_DEV_DIR)

# Apply Kubernetes manifests and mount local source for development
kube-apply-dev: kube-apply kube-mount-dev

# Apply production Kubernetes manifests
kube-apply-prod:
	kubectl apply -f $(KUBE_COMMON_DIR)
	kubectl apply -f $(KUBE_PROD_DIR)

# Create or update GHCR pull secret for production namespace
kube-prod-ghcr-secret:
	@if [ -z "$(GHCR_USERNAME)" ] || [ -z "$(GHCR_TOKEN)" ]; then \
		echo "Error: GHCR_USERNAME and GHCR_TOKEN are required"; \
		echo "Example: make kube-prod-ghcr-secret GHCR_USERNAME=<github-user> GHCR_TOKEN=<github-token>"; \
		exit 1; \
	fi
	kubectl create secret docker-registry ghcr-pull-secret \
		--namespace palad \
		--docker-server=ghcr.io \
		--docker-username="$(GHCR_USERNAME)" \
		--docker-password="$(GHCR_TOKEN)" \
		--dry-run=client -o yaml | kubectl apply -f -

# Default to current directory's web folder if not provided
WEB_HOST_PATH ?= $(shell pwd)

# Apply Kubernetes manifests with a dev hostPath for the web container
kube-mount-dev:
	kubectl patch deployment web -n palad --type='strategic' -p "{\"spec\":{\"template\":{\"spec\":{\"volumes\":[{\"name\":\"web-source\",\"hostPath\":{\"path\":\"$(WEB_HOST_PATH)\",\"type\":\"Directory\"}}],\"containers\":[{\"name\":\"web\",\"volumeMounts\":[{\"name\":\"web-source\",\"mountPath\":\"/app\"}]}]}}}}"
	kubectl rollout restart deployment/web -n palad
	kubectl patch deployment worker-ruby -n palad --type='strategic' -p "{\"spec\":{\"template\":{\"spec\":{\"volumes\":[{\"name\":\"web-source\",\"hostPath\":{\"path\":\"$(WEB_HOST_PATH)\",\"type\":\"Directory\"}}],\"containers\":[{\"name\":\"worker-ruby\",\"volumeMounts\":[{\"name\":\"web-source\",\"mountPath\":\"/app\"}]}]}}}}"
	kubectl rollout restart deployment/worker-ruby -n palad

# Remove Kubernetes manifests
kube-rm:
	kubectl delete -f $(KUBE_DEV_DIR)
	kubectl delete -f $(KUBE_COMMON_DIR)

# Remove production Kubernetes manifests
kube-rm-prod:
	kubectl delete -f $(KUBE_PROD_DIR)
	kubectl delete -f $(KUBE_COMMON_DIR)
