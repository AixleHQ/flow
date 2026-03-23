# Kubernetes targets
.PHONY: kube-help kube-status kube-setup kube-setup-prod kube-setup-staging kube-apply kube-apply-dev kube-apply-prod kube-apply-staging kube-secrets-apply kube-secrets-apply-dev kube-secrets-apply-prod kube-secrets-apply-staging kube-secret-edit kube-web-rollout kube-mount-dev kube-rm kube-rm-prod kube-rm-staging kube-arc-install-controller kube-arc-apply-deploy-rbac kube-arc-install-runner-set kube-arc-install kube-observability-add-repos kube-observability-apply-dashboards kube-observability-install kube-observability-print-headlamp-token kube-observability-uninstall

KUBE_CLUSTER_STORAGECLASS = ./kube/00-storageclass-gp3.yaml
KUBE_DEV_DIR = ./kube/dev
KUBE_PROD_DIR = ./kube/prod
KUBE_STAGING_DIR = ./kube/staging
KUBE_DEV_SECRETS_DIR = ./kube/dev/secrets
KUBE_PROD_SECRETS_DIR = ./kube/prod/secrets
KUBE_STAGING_SECRETS_DIR = ./kube/staging/secrets
TRAEFIK_CRD_URL = https://raw.githubusercontent.com/traefik/traefik/v3.3/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml
KUBE_CONTEXT ?=
KUBE_DEV_NAMESPACE ?= palad-dev
KUBE_PROD_NAMESPACE ?= palad
KUBE_STAGING_NAMESPACE ?= palad-staging
KUBE_NAMESPACE ?= $(KUBE_DEV_NAMESPACE)
SECRET_NAMESPACE ?= $(KUBE_NAMESPACE)
SECRET_NAME ?=
SECRET_KEY ?=
SECRET_VAR ?= $(SECRET_KEY)
SECRET_TYPE ?= Opaque
KUBE_EDITOR ?= vim
KUBECTL = kubectl $(if $(KUBE_CONTEXT),--context $(KUBE_CONTEXT))
ARC_CONTROLLER_INSTALLATION_NAME ?= arc
ARC_CONTROLLER_NAMESPACE ?= arc-system
ARC_RUNNER_INSTALLATION_NAME ?= palad-deploy-runner
ARC_RUNNER_NAMESPACE ?= arc-runners
ARC_RUNNER_VALUES_FILE ?= ./kube/arc/values-runner-scale-set.yaml
KUBE_SETUP_WITH_ARC ?= false

kube-help:
	@echo "Kubernetes commands:"
	@echo "  make kube-status            - Show cluster and namespace health (use KUBE_CONTEXT=... KUBE_NAMESPACE=...)"
	@echo "  make kube-setup             - Build images + apply dev secrets/manifests + run db-prepare"
	@echo "  make kube-setup-prod        - Install Traefik CRDs + apply prod secrets/manifests"
	@echo "  make kube-setup-staging     - Install Traefik CRDs + apply staging secrets/manifests"
	@echo "  make kube-apply             - Apply dev manifests (secrets are not touched)"
	@echo "  make kube-apply-dev         - Apply dev manifests + WEB_HOST_PATH mount for web"
	@echo "  make kube-apply-prod        - Apply prod manifests (secrets are not touched)"
	@echo "  make kube-apply-staging     - Apply staging manifests (secrets are not touched)"
	@echo "  make kube-secrets-apply     - Apply dev secret manifests explicitly"
	@echo "  make kube-secrets-apply-prod    - Apply prod secret manifests explicitly"
	@echo "  make kube-secrets-apply-staging - Apply staging secret manifests explicitly"
	@echo "  make kube-secret-edit       - Edit one decoded secret key and patch it back, creating the secret if missing (SECRET_NAME=... SECRET_KEY=... [SECRET_NAMESPACE=...] [SECRET_TYPE=Opaque])"
	@echo "  make kube-web-rollout       - Rollout restart web, worker-ruby, and mcp deployments"
	@echo "  make kube-arc-install-controller - Install/upgrade ARC controller chart"
	@echo "  make kube-arc-apply-deploy-rbac  - Apply deploy-runner ServiceAccount and rollout RBAC"
	@echo "  make kube-arc-install-runner-set - Install/upgrade ARC runner scale set chart"
	@echo "  make kube-arc-install            - Install ARC controller + deploy RBAC + runner scale set"
	@echo "  make kube-observability-install  - Install/upgrade observability stack via Helm (Prometheus, Loki, Grafana, Alloy, Headlamp, metrics-server)"
	@echo "  make kube-observability-uninstall - Uninstall all observability Helm releases"
	@echo "  make kube-rm                - Delete dev manifests (secrets are not touched)"
	@echo "  make kube-rm-prod           - Delete prod manifests (secrets are not touched)"
	@echo "  make kube-rm-staging        - Delete staging manifests (secrets are not touched)"

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
	$(KUBECTL) apply -f $(KUBE_DEV_DIR)/00-namespace.yaml
	@if [ "$(KUBE_SETUP_WITH_ARC)" = "true" ]; then \
		$(MAKE) kube-arc-install; \
	else \
		echo "Skipping ARC install for local dev (set KUBE_SETUP_WITH_ARC=true to enable)"; \
	fi
	$(KUBECTL) apply -f $(KUBE_DEV_SECRETS_DIR)
	$(KUBECTL) apply -f $(KUBE_DEV_DIR)
	$(KUBECTL) wait --for=condition=ready pod -l app=db -n $(KUBE_DEV_NAMESPACE) --timeout=120s
	$(KUBECTL) exec -n $(KUBE_DEV_NAMESPACE) deployment/web -- rails db:drop DISABLE_DATABASE_ENVIRONMENT_CHECK=1 || true
	$(KUBECTL) exec -n $(KUBE_DEV_NAMESPACE) deployment/web -- make db-prepare
	$(KUBECTL) wait --for=condition=ready pod -l app=web -n $(KUBE_DEV_NAMESPACE) --timeout=120s
	@$(MAKE) kube-mount-dev

# Production Kubernetes setup: CRDs + secrets + production manifests
kube-setup-prod:
	$(KUBECTL) apply -f $(TRAEFIK_CRD_URL)
	$(KUBECTL) apply -f $(KUBE_CLUSTER_STORAGECLASS)
	$(KUBECTL) apply -f $(KUBE_PROD_DIR)/00-namespace.yaml
	$(KUBECTL) apply -f $(KUBE_PROD_SECRETS_DIR)
	@make kube-apply-prod

# Staging Kubernetes setup: CRDs + secrets + staging manifests
kube-setup-staging:
	$(KUBECTL) apply -f $(TRAEFIK_CRD_URL)
	$(KUBECTL) apply -f $(KUBE_CLUSTER_STORAGECLASS)
	$(KUBECTL) apply -f $(KUBE_STAGING_DIR)/00-namespace.yaml
	$(KUBECTL) apply -f $(KUBE_STAGING_SECRETS_DIR)
	@make kube-apply-staging

kube-apply:
	$(KUBECTL) apply -f $(KUBE_DEV_DIR)

# Apply Kubernetes manifests and mount local source for development
kube-apply-dev: kube-apply kube-mount-dev

# Apply production Kubernetes manifests
kube-apply-prod:
	$(KUBECTL) apply -f $(KUBE_PROD_DIR)

# Apply staging Kubernetes manifests
kube-apply-staging:
	$(KUBECTL) apply -f $(KUBE_STAGING_DIR)

# Apply secret manifests only when explicitly requested
kube-secrets-apply: kube-secrets-apply-dev

kube-secrets-apply-dev:
	$(KUBECTL) apply -f $(KUBE_DEV_SECRETS_DIR)

kube-secrets-apply-prod:
	$(KUBECTL) apply -f $(KUBE_PROD_SECRETS_DIR)

kube-secrets-apply-staging:
	$(KUBECTL) apply -f $(KUBE_STAGING_SECRETS_DIR)

# Restart web-related deployments to pick up new config/secrets
kube-web-rollout:
	$(KUBECTL) rollout restart deployment/web deployment/worker-ruby deployment/mcp -n $(KUBE_PROD_NAMESPACE)

# ── Observability stack (Helm) ────────────────────────────────────────────────
OBSERVABILITY_HELM_DIR = ./kube/prod/observability/helm
OBSERVABILITY_EXTRA_DIR = ./kube/prod/observability/extra
OBSERVABILITY_DASHBOARDS_DIR = ./kube/prod/observability/dashboards
MONITORING_NAMESPACE = monitoring

# Add the Helm repos used by the observability stack.
kube-observability-add-repos:
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/
	helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
	helm repo update

# Install or upgrade all observability components via Helm.
# Pre-requisite: create the Grafana admin secret first:
#   make kube-secret-set SECRET_NAMESPACE=monitoring SECRET_NAME=grafana-admin-secret SECRET_KEY=GF_SECURITY_ADMIN_PASSWORD
kube-observability-install: kube-observability-add-repos
	$(KUBECTL) apply -f $(OBSERVABILITY_EXTRA_DIR)/00-namespace.yaml
	@$(MAKE) kube-observability-apply-dashboards
	helm upgrade --install metrics-server metrics-server/metrics-server \
		--namespace kube-system \
		--values $(OBSERVABILITY_HELM_DIR)/values-metrics-server.yaml \
		--wait
	helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
		--namespace $(MONITORING_NAMESPACE) \
		--values $(OBSERVABILITY_HELM_DIR)/values-kube-prometheus-stack.yaml \
		--wait
	helm upgrade --install loki grafana/loki \
		--namespace $(MONITORING_NAMESPACE) \
		--values $(OBSERVABILITY_HELM_DIR)/values-loki.yaml \
		--wait
	helm upgrade --install alloy grafana/alloy \
		--namespace $(MONITORING_NAMESPACE) \
		--values $(OBSERVABILITY_HELM_DIR)/values-alloy.yaml \
		--wait
	helm upgrade --install headlamp headlamp/headlamp \
		--namespace $(MONITORING_NAMESPACE) \
		--values $(OBSERVABILITY_HELM_DIR)/values-headlamp.yaml \
		--wait
	$(KUBECTL) apply -f $(OBSERVABILITY_EXTRA_DIR)/01-ingressroutes.yaml
	$(KUBECTL) apply -f $(OBSERVABILITY_EXTRA_DIR)/02-headlamp-access.yaml

# Provision Grafana dashboards from version-controlled JSON files.
kube-observability-apply-dashboards:
	$(KUBECTL) create configmap grafana-dashboard-k8s-views-global \
		-n $(MONITORING_NAMESPACE) \
		--from-file=k8s-views-global.json=$(OBSERVABILITY_DASHBOARDS_DIR)/k8s-views-global.json \
		--dry-run=client -o yaml | \
		$(KUBECTL) label --local -f - grafana_dashboard=1 -o yaml | \
		$(KUBECTL) apply -f -

kube-observability-print-headlamp-token:
	@$(KUBECTL) create token headlamp-admin -n $(MONITORING_NAMESPACE); echo

# Uninstall all observability Helm releases.
kube-observability-uninstall:
	helm uninstall metrics-server --namespace kube-system || true
	helm uninstall kube-prometheus-stack --namespace $(MONITORING_NAMESPACE) || true
	helm uninstall loki --namespace $(MONITORING_NAMESPACE) || true
	helm uninstall alloy --namespace $(MONITORING_NAMESPACE) || true
	helm uninstall headlamp --namespace $(MONITORING_NAMESPACE) || true
	$(KUBECTL) delete configmap grafana-dashboard-k8s-views-global -n $(MONITORING_NAMESPACE) --ignore-not-found=true
	$(KUBECTL) delete -f $(OBSERVABILITY_EXTRA_DIR)/02-headlamp-access.yaml || true
	$(KUBECTL) delete -f $(OBSERVABILITY_EXTRA_DIR)/01-ingressroutes.yaml || true

# Install/upgrade Actions Runner Controller (ARC) controller chart.
kube-arc-install-controller:
	helm upgrade --install "$(ARC_CONTROLLER_INSTALLATION_NAME)" \
		oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
		--namespace "$(ARC_CONTROLLER_NAMESPACE)" \
		--create-namespace

# Apply runner service account in arc-runners and rollout RBAC in the prod namespace.
kube-arc-apply-deploy-rbac:
	$(KUBECTL) apply -f ./kube/arc/01-deploy-runner-rbac.yaml
	$(KUBECTL) apply -f ./kube/arc/02-deploy-runner-rbac-staging.yaml

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

# Edit one decoded secret key interactively and patch it back to the cluster.
# If the secret does not exist yet, create it first using SECRET_TYPE (default: Opaque).
kube-secret-edit:
	@set -eu; \
	if [ -z "$(SECRET_NAME)" ]; then \
		echo "SECRET_NAME is not set. Available secrets in namespace $(SECRET_NAMESPACE):"; \
		$(KUBECTL) get secrets -n "$(SECRET_NAMESPACE)" || true; \
		echo "Usage: make kube-secret-edit SECRET_NAME=<secret-name> SECRET_KEY=<env-var-name> [SECRET_NAMESPACE=$(KUBE_DEV_NAMESPACE)] [SECRET_TYPE=Opaque] [KUBE_EDITOR=vim]"; \
		exit 1; \
	fi; \
	secret_key="$(if $(SECRET_VAR),$(SECRET_VAR),$(SECRET_KEY))"; \
	if [ -z "$$secret_key" ]; then \
		echo "SECRET_KEY is not set. Available keys in $(SECRET_NAME):"; \
		$(KUBECTL) get secret "$(SECRET_NAME)" -n "$(SECRET_NAMESPACE)" -o json | jq -r '.data | keys[]?' || true; \
		echo "Usage: make kube-secret-edit SECRET_NAME=<secret-name> SECRET_KEY=<env-var-name> [SECRET_NAMESPACE=$(KUBE_DEV_NAMESPACE)] [SECRET_TYPE=Opaque] [KUBE_EDITOR=vim]"; \
		exit 1; \
	fi; \
	tmp_file="$$(mktemp /tmp/kube-secret-edit.XXXXXX)"; \
	patch_file="$$(mktemp /tmp/kube-secret-edit-patch.XXXXXX)"; \
	cleanup() { rm -f "$$tmp_file" "$$patch_file"; }; \
	trap cleanup EXIT INT TERM; \
	if $(KUBECTL) get secret "$(SECRET_NAME)" -n "$(SECRET_NAMESPACE)" >/dev/null 2>&1; then \
		current_value="$$( $(KUBECTL) get secret "$(SECRET_NAME)" -n "$(SECRET_NAMESPACE)" -o json | jq -r --arg key "$$secret_key" '.data[$$key] // empty' )"; \
	else \
		echo "Secret $(SECRET_NAME) not found in namespace $(SECRET_NAMESPACE); creating it with type $(SECRET_TYPE)."; \
		$(KUBECTL) create secret generic "$(SECRET_NAME)" -n "$(SECRET_NAMESPACE)" --type "$(SECRET_TYPE)" --from-literal "$$secret_key=" >/dev/null; \
		current_value=""; \
	fi; \
	if [ -n "$$current_value" ]; then \
		printf '%s' "$$current_value" | base64 -d > "$$tmp_file"; \
	fi; \
	echo "Editing $(SECRET_NAME)/$$secret_key in namespace $(SECRET_NAMESPACE)"; \
	KUBE_SECRET_FILE="$$tmp_file" KUBE_EDITOR_CMD='$(KUBE_EDITOR)' sh -c 'exec $$KUBE_EDITOR_CMD "$$KUBE_SECRET_FILE"'; \
	encoded_value="$$(perl -0pe 's/\n\z//' "$$tmp_file" | base64 | tr -d '\n')"; \
	jq -n --arg key "$$secret_key" --arg value "$$encoded_value" '{data: {($$key): $$value}}' > "$$patch_file"; \
	$(KUBECTL) patch secret "$(SECRET_NAME)" -n "$(SECRET_NAMESPACE)" --type merge --patch-file "$$patch_file" >/dev/null; \
	echo "Updated $(SECRET_NAME)/$$secret_key in namespace $(SECRET_NAMESPACE)"

# Default to current directory's web folder if not provided
WEB_HOST_PATH ?= $(shell pwd)

# Apply Kubernetes manifests with a dev hostPath for the web container
kube-mount-dev:
	$(KUBECTL) patch deployment web -n $(KUBE_DEV_NAMESPACE) --type='strategic' -p "{\"spec\":{\"template\":{\"spec\":{\"volumes\":[{\"name\":\"web-source\",\"hostPath\":{\"path\":\"$(WEB_HOST_PATH)\",\"type\":\"Directory\"}}],\"containers\":[{\"name\":\"web\",\"volumeMounts\":[{\"name\":\"web-source\",\"mountPath\":\"/app\"}]}]}}}}"
	$(KUBECTL) rollout restart deployment/web -n $(KUBE_DEV_NAMESPACE)
	$(KUBECTL) patch deployment worker-ruby -n $(KUBE_DEV_NAMESPACE) --type='strategic' -p "{\"spec\":{\"template\":{\"spec\":{\"volumes\":[{\"name\":\"web-source\",\"hostPath\":{\"path\":\"$(WEB_HOST_PATH)\",\"type\":\"Directory\"}}],\"containers\":[{\"name\":\"worker-ruby\",\"volumeMounts\":[{\"name\":\"web-source\",\"mountPath\":\"/app\"}]}]}}}}"
	$(KUBECTL) rollout restart deployment/worker-ruby -n $(KUBE_DEV_NAMESPACE)
	$(KUBECTL) patch deployment mcp -n $(KUBE_DEV_NAMESPACE) --type='strategic' -p "{\"spec\":{\"template\":{\"spec\":{\"volumes\":[{\"name\":\"web-source\",\"hostPath\":{\"path\":\"$(WEB_HOST_PATH)\",\"type\":\"Directory\"}}],\"containers\":[{\"name\":\"mcp\",\"volumeMounts\":[{\"name\":\"web-source\",\"mountPath\":\"/app\"}]}]}}}}"
	$(KUBECTL) rollout restart deployment/mcp -n $(KUBE_DEV_NAMESPACE)

# Remove Kubernetes manifests
kube-rm:
	$(KUBECTL) delete -f $(KUBE_DEV_DIR)

# Remove production Kubernetes manifests
kube-rm-prod:
	$(KUBECTL) delete -f $(KUBE_PROD_DIR)

# Remove staging Kubernetes manifests
kube-rm-staging:
	$(KUBECTL) delete -f $(KUBE_STAGING_DIR)
