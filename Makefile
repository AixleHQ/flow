# Application Management
.PHONY: deps db-prepare db-reset check check_all be_check fe_check lint typescript test rails-test fe-test rubocop rubocop-fix eslint eslint-fix fsd fsd-fix db_dump db_restore db_restore_remote brakeman license-report license-report-ruby license-report-js default ensure-env check-env setup up start down reset doctor worker shell build-web build-otlp-ingest build-agents restore-dump help

DOCKER_COMPOSE ?= docker compose

TODAY = $$(date +"%d.%m.%Y")
LICENSE_REPORTS_DIR := tmp/license-reports

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

# Run all checks in parallel, never short-circuit, summarize at the end.
# Each check writes its output to tmp/check_results/<name>.log and exit code to <name>.status.
# Failures are surfaced together (with last 80 log lines each) so you can fix them in one pass.
CHECK_RESULTS := tmp/check_results
check_all:
	@rm -rf $(CHECK_RESULTS) && mkdir -p $(CHECK_RESULTS)
	@echo "Running rails-test, rubocop, brakeman, eslint, typescript in parallel..."
	@( bundle exec rails test                                       > $(CHECK_RESULTS)/rails-test.log 2>&1; echo $$? > $(CHECK_RESULTS)/rails-test.status ) & \
	 ( bundle exec rubocop                                          > $(CHECK_RESULTS)/rubocop.log    2>&1; echo $$? > $(CHECK_RESULTS)/rubocop.status )    & \
	 ( bundle exec brakeman -q -z --no-pager --skip-files public/   > $(CHECK_RESULTS)/brakeman.log   2>&1; echo $$? > $(CHECK_RESULTS)/brakeman.status )   & \
	 ( yarn lint                                                    > $(CHECK_RESULTS)/eslint.log     2>&1; echo $$? > $(CHECK_RESULTS)/eslint.status )     & \
	 ( yarn tsc                                                     > $(CHECK_RESULTS)/typescript.log 2>&1; echo $$? > $(CHECK_RESULTS)/typescript.status ) & \
	 wait
	@echo ""
	@echo "=== Summary ==="
	@fail=0; for f in $(CHECK_RESULTS)/*.status; do \
	  name=$$(basename $$f .status); \
	  status=$$(cat $$f); \
	  if [ "$$status" = "0" ]; then \
	    printf "  [OK]   %s\n" "$$name"; \
	  else \
	    printf "  [FAIL] %s (exit %s)\n" "$$name" "$$status"; \
	    fail=1; \
	  fi; \
	done; \
	if [ $$fail -ne 0 ]; then \
	  echo ""; \
	  echo "=== Failure output (last 80 lines per failed check) ==="; \
	  for f in $(CHECK_RESULTS)/*.status; do \
	    name=$$(basename $$f .status); \
	    status=$$(cat $$f); \
	    if [ "$$status" != "0" ]; then \
	      echo ""; \
	      echo "--- $$name (full log: $(CHECK_RESULTS)/$$name.log) ---"; \
	      tail -80 $(CHECK_RESULTS)/$$name.log; \
	    fi; \
	  done; \
	  exit 1; \
	fi

# Run backend checks
be_check: rails-test rubocop-fix brakeman

# Run frontend checks
fe_check: eslint-fix typescript

# Run all linters
lint: eslint-fix rubocop-fix brakeman typescript

# Run TypeScript compiler check
typescript:
	yarn tsc

# Run all tests
test: rails-test

# Run Rails tests
rails-test:
	bundle exec rails test

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

# Generate Ruby gem license report (markdown)
license-report-ruby:
	@mkdir -p $(LICENSE_REPORTS_DIR)
	bundle exec license_finder report --format=markdown --enabled-package-managers=bundler > $(LICENSE_REPORTS_DIR)/gem-licenses.md

# Generate npm production dependency license report (markdown)
license-report-js:
	@mkdir -p $(LICENSE_REPORTS_DIR)
	yarn license-checker-rseidelsohn --markdown --production > $(LICENSE_REPORTS_DIR)/npm-licenses.md

# Generate all dependency license reports
license-report: license-report-ruby license-report-js

# Default target
default: check

ensure-env:
	@bin/ensure-env

check-env:
	@bin/check-env

# Cold path: build images and install all dependencies into volumes
setup: ensure-env check-env
	$(DOCKER_COMPOSE) build
	$(DOCKER_COMPOSE) up -d db
	$(DOCKER_COMPOSE) run --rm --no-deps web bin/docker-bootstrap install
	@make build-agents

# Warm path: start all services with fast dependency check
up: ensure-env check-env
	$(DOCKER_COMPOSE) up

# First-time setup and start in one command
start: setup up

down:
	$(DOCKER_COMPOSE) down

reset:
	$(DOCKER_COMPOSE) down -v
	rm -f tmp/bootstrap.stamp

doctor:
	@bin/doctor

# Backward compat alias
worker:
	$(DOCKER_COMPOSE) up worker

# Open shell in web container
shell:
	$(DOCKER_COMPOSE) run --rm --no-deps web bash

# Restore a locally available database dump
restore-dump:
	$(DOCKER_COMPOSE) run --rm --no-deps web make db_restore

build-web:
	docker build -f Dockerfile -t web .

build-otlp-ingest:
	docker build -f docker/otlp-ingest/Dockerfile -t otlp-ingest docker/otlp-ingest

# Build agent images (core first, then agents in parallel)
build-agents:
	docker build -t aixle/agent-base-core:latest -f docker/base/Dockerfile docker/base
	docker build -t aixle/claude-code:latest -f docker/claude-code/Dockerfile docker/ & \
	docker build -t aixle/cursor-cli:latest -f docker/cursor-cli/Dockerfile docker/ & \
	docker build -t aixle/codex:latest -f docker/codex/Dockerfile docker/ & \
	docker build -t aixle/gemini-cli:latest -f docker/gemini-cli/Dockerfile docker/ & \
	wait

# Help command
help:
	@echo "Available commands:"
	@echo "  make setup                  - Build images and install all dependencies (first-time setup)"
	@echo "  make start                  - setup + up (full first-time bootstrap and run)"
	@echo "  make up                     - Start all services (web, worker, db, redis, temporal, ...)"
	@echo "  make down                   - Stop all containers"
	@echo "  make reset                  - Stop containers and remove volumes (destructive)"
	@echo "  make doctor                 - Check local dev environment health"
	@echo "  make worker                 - Start worker only (backward compat alias)"
	@echo "  make deps                   - Setup dependencies"
	@echo "  make db-prepare             - Prepare database (create, migrate, seed)"
	@echo "  make db-reset               - Reset database (drop, create, migrate, seed)"
	@echo "  make check                  - Run all linters and tests (sequential, stops on first failure)"
	@echo "  make check_all              - Run all checks in parallel, summarize failures at the end"
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
	@echo "  make license-report         - Generate Ruby and npm license reports"
	@echo "  make license-report-ruby    - Generate Ruby gem license report"
	@echo "  make license-report-js      - Generate npm production license report"
	@echo "  make db_restore_remote      - Restore database remotely"
	@echo "  make restore-dump           - Restore a locally available database dump"
	@echo "  make default                - Same as 'check'"
	@echo "  make help                   - Show this help message"
	@echo "  make shell                  - Open shell in web container"
	@echo ""
	@echo "Agent Docker Images:"
	@echo "  make build-agents           - Build all agent images (core + 4 agents in parallel)"
	@echo "  make build-otlp-ingest      - Build the OTLP ingest image"
