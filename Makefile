# AI Engine Docker Management
.PHONY: setup lint test run shell-web shell-ai-engine login_aws qa-web-exec qa-web-logs qa-web-watch-logs prod-web-exec prod-web-logs prod-web-watch-logs dump-qa dump-prod fetch-qa-dump fetch-prod-dump restore-dump restore-qa-db restore-prod-db build-agents setup-kube kube-apply kube-apply-dev kube-rm help

TODAY = $$(date +"%d.%m.%Y")

# Setup dependencies
deps:
	bundle install
	yarn install

# Prepare database
db-prepare:
	bundle exec rails db:create db:migrate db:seed

# Reset database
db-reset:
	bundle exec rails db:drop db:create db:migrate db:seed

# Run all linters and tests
check: be_check fe_check

# Run backend checks
be_check: rails-test rubocop-fix brakeman

# Run frontend checks
fe_check: eslint-fix fsd typescript

# Run all linters
lint: fsd eslint-fix rubocop-fix makebrakeman typescript

# Run TypeScript compiler check
typescript:
	yarn tsc

# Run all tests
test: rails-test fe-test

# Run Rails tests
rails-test:
	bundle exec rails test

# Run frontend tests
fe-test:
	yarn test

# Run Rubocop
rubocop:
	bundle exec rubocop

# Run Rubocop with auto-correction
rubocop-fix:
	bundle exec rubocop -a

# Run ESLint
eslint:
	yarn lint

# Run ESLint with auto-correction
eslint-fix:
	yarn lint:fix

fsd:
	yarn run steiger app/frontend

fsd-fix:
	yarn run steiger app/frontend --fix

db_dump:
	pg_dump --no-owner --no-privileges -c "postgresql://${DB_USERNAME}:${DB_PASSWORD}@${DB_HOST}/${DB_NAME}" | gzip > ${TODAY}.sql.gz
	FILE=${TODAY}.sql.gz BUCKET_KEY=db_dumps/${TODAY}.sql.gz bundle exec rake s3:upload
	FILE=${TODAY}.sql.gz BUCKET_KEY=db_dumps/latest.sql.gz bundle exec rake s3:upload

db_restore:
	bundle exec rails db:environment:set RAILS_ENV=development
	bundle exec rails db:drop db:create
	gunzip < /db_dumps/latest.sql.gz | psql -h ${DB_HOST} -U ${DB_USERNAME} ${DB_NAME}
	bundle exec rails db:migrate

db_restore_remote:
	BUCKET_KEY=db_dumps/latest.sql.gz bundle exec rake s3:download
	export PGPASSWORD=${DATABASE_PASSWORD}; gunzip < latest.sql.gz | psql -h ${DATABASE_HOST} -U ${DATABASE_USER} ${DATABASE_NAME}

# Run Brakeman security analysis
brakeman:
	bundle exec brakeman -q -z --no-pager --skip-files public/

# Default target
default: check

# Setup project in one command
setup:
	docker-compose --profile worker build
	docker-compose run --rm web make deps db-prepare

# Full Kubernetes setup: CRDs, manifests, wait for pods, migrate and seed
kube-setup:
	@make build-web
	@make build-otlp-ingest
	@make build-agents
	kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v3.3/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml
	kubectl apply -f ./kube
	kubectl wait --for=condition=ready pod -l app=db -n palad --timeout=120s
	kubectl wait --for=condition=ready pod -l app=web -n palad --timeout=120s
	kubectl exec -n palad deployment/web -- make db-prepare
	@make kube-mount-dev

kube-apply:
	kubectl apply -f ./kube

# Default to current directory's web folder if not provided
WEB_HOST_PATH ?= $(shell pwd)/web

# Apply Kubernetes manifests with a dev hostPath for the web container
kube-mount-dev:
	kubectl patch deployment web -n palad --type='json' -p='[{"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"web-source","hostPath":{"path":"$(WEB_HOST_PATH)","type":"Directory"}}},{"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"web-source","mountPath":"/app"}}]'
	kubectl rollout restart deployment/web -n palad
	kubectl patch deployment worker-ruby -n palad --type='json' -p='[{"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"web-source","hostPath":{"path":"$(WEB_HOST_PATH)","type":"Directory"}}},{"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"web-source","mountPath":"/app"}}]'
	kubectl rollout restart deployment/worker-ruby -n palad

# Remove Kubernetes manifests
kube-rm:
	kubectl delete -f ./kube

# Run all main services
up:
	docker-compose up

# Run worker
worker:
	docker-compose --profile worker up --no-deps worker

# Open shell in web container
shell:
	docker-compose run --rm web bash

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

build-web:
	docker build -f web/Dockerfile -t web .

build-otlp-ingest:
	docker build -f docker/otlp-ingest/Dockerfile -t otlp-ingest docker/otlp-ingest

# Build agent images (core first, then agents in parallel)
build-agents:
	docker build -t palad/agent-base-core:latest -f docker/base/Dockerfile.core docker/base
	docker build -t palad/claude-code:latest -f docker/claude-code/Dockerfile docker/ & \
	docker build -t palad/cursor-cli:latest -f docker/cursor-cli/Dockerfile docker/ & \
	docker build -t palad/codex:latest -f docker/codex/Dockerfile docker/ & \
	docker build -t palad/gemini-cli:latest -f docker/gemini-cli/Dockerfile docker/ & \
	wait

# Help command
help:
	@echo "Available commands:"
	@echo "  make setup                  - Setup project in one command"
	@echo "  make shell                  - Open shell in web container"
	@echo "  make deps                   - Setup dependencies"
	@echo "  make db-prepare             - Prepare database (create, migrate, seed)"
	@echo "  make db-reset               - Reset database (drop, create, migrate, seed)"
	@echo "  make check                  - Run all linters and tests"
	@echo "  make lint                   - Run all linters (rubocop, eslint, brakeman)"
	@echo "  make test                   - Run all tests"
	@echo "  make rails-test             - Run Rails tests"
	@echo "  make fe-test                - Run frontend tests"
	@echo "  make rubocop                - Run Rubocop"
	@echo "  make rubocop-fix            - Run Rubocop with auto-correction"
	@echo "  make eslint                 - Run ESLint"
	@echo "  make eslint-fix             - Run ESLint with auto-correction"
	@echo "  make typescript             - Run TypeScript compiler check"
	@echo "  make brakeman               - Run Brakeman security analysis"
	@echo "  make db_restore_remote      - Restore database remotely"
	@echo "  make default                - Same as 'check'"
	@echo "  make help                   - Show this help message"
	@echo "  make kube-setup             - Apply Kubernetes manifests"
	@echo "  make kube-apply             - Apply Kubernetes manifests only"
	@echo "  make kube-apply-dev          - Apply manifests with WEB_HOST_PATH for web"
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
	@echo "  make build-agents           - Build all agent images (core + 4 agents in parallel)"
	@echo "  make build-otlp-ingest      - Build the OTLP ingest image"
	@echo ""
	@echo "  make help                   - Show this help message"
