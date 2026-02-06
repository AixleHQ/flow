# AI Engine Docker Management
.PHONY: setup run shell-web shell-ai-engine login_aws qa-web-exec qa-web-logs qa-web-watch-logs prod-web-exec prod-web-logs prod-web-watch-logs dump-qa dump-prod fetch-qa-dump fetch-prod-dump restore-dump restore-qa-db restore-prod-db build-agents setup-kube kube-apply kube-rm help

# Setup project in one command
setup:
	docker-compose --profile worker build
	docker-compose run --rm web make deps db-prepare

# Apply Kubernetes manifests
kube-setup:
	kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v3.3/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml

# Apply Kubernetes manifests only
kube-apply:
	kubectl apply -f /workspaces/palad-app/kube

# Remove Kubernetes manifests
kube-rm:
	kubectl delete -f /workspaces/palad-app/kube

# Run all main services
up:
	docker-compose up

# Run workers
workers:
	docker-compose --profile worker up --no-deps worker-ruby

# Open shell in web container
shell-web:
	docker-compose run --rm web bash

# Open shell in ai engine container
shell-ai-engine:
	docker-compose run --rm worker-python bash

# Login to AWS account with AWS-Vault
login_aws:
	aws-vault login $(PROFILE) -t $(shell op item get "terraform palad" --otp)

# Execute into QA web container
qa-web-exec:
	aws-vault exec $(PROFILE) -t $(shell op item get "terraform palad" --otp) -- docker-compose run --rm remote make exec_qa_web

# Show logs from QA web container
qa-web-logs:
	aws-vault exec $(PROFILE) -t $(shell op item get "terraform palad" --otp) -- docker-compose run --rm remote make qa_web_logs

# Watch logs from QA web container
qa-web-watch-logs:
	aws-vault exec $(PROFILE) -t $(shell op item get "terraform palad" --otp) -- docker-compose run --rm remote make watch_qa_web_logs

# Execute into prod web container
prod-web-exec:
	aws-vault exec $(PROFILE) -t $(shell op item get "terraform palad" --otp) -- docker-compose run --rm remote make exec_prod_web

# Show logs from prod web container
prod-web-logs:
	aws-vault exec $(PROFILE) -t $(shell op item get "terraform palad" --otp) -- docker-compose run --rm remote make prod_web_logs

# Watch logs from prod web container
prod-web-watch-logs:
	aws-vault exec $(PROFILE) -t $(shell op item get "terraform palad" --otp) -- docker-compose run --rm remote make watch_prod_web_logs

# Database dump operations
dump-qa:
	aws-vault exec $(PROFILE) -t $(shell op item get "terraform palad" --otp) -- docker-compose run --rm remote make dump_qa

dump-prod:
	aws-vault exec $(PROFILE) -t $(shell op item get "terraform palad" --otp) -- docker-compose run --rm remote make dump_prod

fetch-qa-dump:
	aws-vault exec $(PROFILE) -t $(shell op item get "terraform palad" --otp) -- docker-compose run --rm remote make fetch_qa_dump

fetch-prod-dump:
	aws-vault exec $(PROFILE) -t $(shell op item get "terraform palad" --otp) -- docker-compose run --rm remote make fetch_prod_dump

restore-dump:
	docker-compose run --rm web make db_restore

restore-qa-db: dump-qa fetch-qa-dump restore-dump

restore-prod-db: dump-prod fetch-prod-dump restore-dump

# Build agent images
build-agents:
	docker build -t palad/agent-base:latest docker/base
	docker build -t palad/claude-code:latest docker/claude-code
	docker build -t palad/cursor-cli:latest docker/cursor-cli
	docker build -t palad/codex:latest docker/codex
	docker build -t palad/gemini-cli:latest docker/gemini-cli

# Help command
help:
	@echo "Available commands:"
	@echo "  make setup                  - Setup project in one command"
	@echo "  make kube-setup             - Apply Kubernetes manifests"
	@echo "  make kube-apply             - Apply Kubernetes manifests only"
	@echo "  make kube-rm                - Delete Kubernetes manifests"
	@echo "  make up                     - Run all main services"
	@echo "  make workers                - Run workers (3 Python + 1 Ruby)"
	@echo "  make shell-web              - Open shell in web container"
	@echo "  make shell-ai-engine        - Open shell in ai-engine container"
	@echo "  make browser-tools-server   - Run browser tools server"
	@echo ""
	@echo "AWS Operations (require PROFILE=profile_name):"
	@echo "  make login_aws              - Login to AWS account with AWS-Vault"
	@echo "  make qa-web-exec            - Execute into QA web container"
	@echo "  make qa-web-logs            - Show logs from QA web container"
	@echo "  make qa-web-watch-logs      - Watch logs from QA web container in real-time"
	@echo "  make prod-web-exec          - Execute into Production web container"
	@echo "  make prod-web-logs          - Show logs from Production web container"
	@echo "  make prod-web-watch-logs    - Watch logs from Production web container in real-time"
	@echo ""
	@echo "Database Operations (require PROFILE=profile_name):"
	@echo "  make dump-qa                - Create database dump on QA environment and upload to S3"
	@echo "  make dump-prod              - Create database dump on Production environment and upload to S3"
	@echo "  make fetch-qa-dump          - Download latest QA database dump from S3"
	@echo "  make fetch-prod-dump        - Download latest Production database dump from S3"
	@echo "  make restore-dump           - Restore database dump locally"
	@echo "  make restore-qa-db          - Full cycle: dump QA DB, fetch it, and restore locally"
	@echo "  make restore-prod-db        - Full cycle: dump Production DB, fetch it, and restore locally"
	@echo ""
	@echo ""
	@echo "Agent Docker Images:"
	@echo "  make build-agents           - Build all agent images (base + 4 agents)"
	@echo ""
	@echo "  make help                   - Show this help message"
