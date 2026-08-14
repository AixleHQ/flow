# Application Management
.PHONY: deps db-prepare db-reset check check_all be_check_all fe_check_all be_check fe_check lint typescript test rails-test fe-test rubocop rubocop-fix eslint eslint-fix fsd fsd-fix db_dump db_restore db_restore_remote brakeman license-report license-report-ruby license-report-js default setup git-hooks up down reset worker shell build-web build-otlp-ingest build-agents restore-dump help

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

# CI checks. Each check writes tmp/check_results/<name>.log + <name>.status so a batch never
# short-circuits and every failure is surfaced together. CI runs frontend and backend as SEPARATE
# jobs (see .github/workflows/deploy.yml) so Vitest never competes with the Ruby suite for CPU;
# `check_all` keeps the combined one-command run for local use.
CHECK_RESULTS := tmp/check_results

# Backend coverage floor, enforced only on full-suite runs (see test/test_helper.rb).
# Ratchet upward as coverage grows — never lower it. Measured 88.3% on 2026-07-06.
COVERAGE_MIN := 85

# Coverage gating (task #288). SimpleCov (backend) and v8 all:true (frontend)
# instrumentation are a large multiplier on suite runtime, so CI only runs coverage
# on the develop branch — the integration gate — and skips it on ordinary feature-branch
# pushes to keep the Checks/Run stage fast. The branch→coverage decision is made in the
# workflow config (deploy.yml "Prepare Config" job), which sets the run_coverage output
# and forwards it into the container as RUN_COVERAGE (see code-check.yml /
# docker-compose.ci.yml). This Makefile just honors that flag. When RUN_COVERAGE is
# unset/empty (local `make check_all`/`rails-test`) it defaults to 1 so the pre-push gate
# keeps enforcing the floor.
RUN_COVERAGE ?= 1
ifeq ($(strip $(RUN_COVERAGE)),)
  RUN_COVERAGE := 1
endif

ifeq ($(strip $(RUN_COVERAGE)),1)
  # Enforce the backend floor and produce a coverage report.
  RAILS_TEST_COV_ENV := COVERAGE_MIN=$(COVERAGE_MIN)
  # Frontend: run Vitest with v8 coverage + thresholds (vitest.config.ts).
  FE_TEST_CMD := yarn test --coverage
else
  # Skip SimpleCov instrumentation entirely (test_helper.rb honors SKIP_COVERAGE).
  RAILS_TEST_COV_ENV := SKIP_COVERAGE=1
  # Frontend: run Vitest without coverage instrumentation/thresholds.
  FE_TEST_CMD := yarn test
endif

# Two concurrent `rails test` invocations are mutually destructive: parallel test
# workers drop/recreate the shared aixle_test_N databases, so overlapping runs
# corrupt each other's schemas (observed 2026-07-03: pg_class duplicate-key storms).
# flock serializes make-driven suite runs (BusyBox flock: blocking exclusive lock,
# no timeout flag); runs started outside make must still never overlap — coordinate
# agent sessions working in the same checkout/worktrees.
TEST_LOCK := flock tmp/.rails-test.lock

# Backend (Ruby) checks, in parallel. Each subshell records its own exit code, so `wait` never aborts.
define run_be_checks
	@echo "Building test-mode Vite assets (required: test uses built assets, autoBuild is off)..."
	@# VITE_RUBY_MODE=test selects the vite-test publicOutputDir (a bare `--mode test`
	@# only sets Vite's JS mode, NOT ViteRuby's output dir → it'd build to vite-dev).
	@# --force so a stale last-compilation digest never skips the build (leaving no manifest).
	@# env -u VITE_RUBY_ASSET_HOST -u ASSET_HOST: the deploy image bakes ASSET_HOST=
	@# https://static.flow.aixle.com into VITE_RUBY_ASSET_HOST (Dockerfile ENV), which Vite
	@# would otherwise stamp as the base of every dynamic-import chunk URL. On CI the browser
	@# then fetches chunks from the CDN (which has no freshly-built test chunks) → 404 → the
	@# React SPA never mounts → system tests fail "Unable to find field Email". Unset it so
	@# test chunks resolve relative to the Capybara test server.
	@( env -u VITE_RUBY_ASSET_HOST -u ASSET_HOST VITE_RUBY_MODE=test bin/vite build --force > $(CHECK_RESULTS)/vite-build.log 2>&1; echo $$? > $(CHECK_RESULTS)/vite-build.status )
	@echo "Running rails-test, rubocop, brakeman, system-test in parallel (DB-touching runs serialized by flock)..."
	@( $(RAILS_TEST_COV_ENV) $(TEST_LOCK) bundle exec rails test > $(CHECK_RESULTS)/rails-test.log 2>&1; echo $$? > $(CHECK_RESULTS)/rails-test.status ) & \
	 ( SKIP_COVERAGE=1 $(TEST_LOCK) bundle exec rails test:system   > $(CHECK_RESULTS)/system-test.log 2>&1; echo $$? > $(CHECK_RESULTS)/system-test.status ) & \
	 ( bundle exec rubocop                                          > $(CHECK_RESULTS)/rubocop.log    2>&1; echo $$? > $(CHECK_RESULTS)/rubocop.status )    & \
	 ( bundle exec brakeman -q -z --no-pager --skip-files public/   > $(CHECK_RESULTS)/brakeman.log   2>&1; echo $$? > $(CHECK_RESULTS)/brakeman.status )   & \
	 wait
endef

# Frontend (JS/TS) checks. eslint + tsc run in parallel; Vitest then runs ON ITS OWN. Vitest spawns a
# worker per core and (with coverage's all:true) instruments the whole frontend, so racing it against
# tsc/eslint — let alone the Ruby suite in the old all-in-one check_all — CPU-starved the heaviest
# jsdom+userEvent form tests past their timeout: green in isolation, flaky only under the full load.
define run_fe_checks
	@echo "Running eslint, typescript in parallel..."
	@( yarn lint                                                    > $(CHECK_RESULTS)/eslint.log     2>&1; echo $$? > $(CHECK_RESULTS)/eslint.status )     & \
	 ( yarn tsc                                                     > $(CHECK_RESULTS)/typescript.log 2>&1; echo $$? > $(CHECK_RESULTS)/typescript.status ) & \
	 wait
	@echo "Running fe-test (Vitest$(if $(filter 1,$(RUN_COVERAGE)), + coverage,)) on its own..."
	@( $(FE_TEST_CMD)                                               > $(CHECK_RESULTS)/fe-test.log    2>&1; echo $$? > $(CHECK_RESULTS)/fe-test.status )
endef

# Summarize every tmp/check_results/*.status, print whichever coverage files exist, dump the full log
# of each failed check, and exit non-zero if any failed.
define summarize_checks
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
	echo ""; \
	echo "=== Coverage (line %) ==="; \
	if [ -f coverage/.last_run.json ]; then \
	  be=$$(ruby -rjson -e 'begin; puts JSON.parse(File.read("coverage/.last_run.json"))["result"]["line"]; rescue; puts "n/a"; end' 2>/dev/null); \
	  stale=""; \
	  if [ -f $(CHECK_RESULTS)/rails-test.status ] && [ "$$(cat $(CHECK_RESULTS)/rails-test.status)" != "0" ]; then \
	    stale=" (may be stale: simplecov rewrites .last_run.json only on a passing run — real value is in rails-test.log)"; \
	  fi; \
	  printf "  backend  (rails / simplecov): %s%%%s\n" "$$be" "$$stale"; \
	fi; \
	if [ -f coverage/frontend/coverage-summary.json ]; then \
	  fe=$$(ruby -rjson -e 'begin; puts JSON.parse(File.read("coverage/frontend/coverage-summary.json"))["total"]["lines"]["pct"]; rescue; puts "n/a"; end' 2>/dev/null); \
	  printf "  frontend (vitest / v8):       %s%%\n" "$$fe"; \
	fi; \
	if [ ! -f coverage/.last_run.json ] && [ ! -f coverage/frontend/coverage-summary.json ]; then \
	  printf "  (skipped — coverage instrumentation runs only when RUN_COVERAGE=1: develop CI and local check_all)\n"; \
	fi; \
	if [ $$fail -ne 0 ]; then \
	  echo ""; \
	  echo "=== Failure output (full log per failed check) ==="; \
	  for f in $(CHECK_RESULTS)/*.status; do \
	    name=$$(basename $$f .status); \
	    status=$$(cat $$f); \
	    if [ "$$status" != "0" ]; then \
	      echo ""; \
	      echo "--- $$name (exit $$status) ---"; \
	      cat $(CHECK_RESULTS)/$$name.log; \
	    fi; \
	  done; \
	  exit 1; \
	fi
endef

# Backend checks only (CI runs this in the backend job).
be_check_all:
	@rm -rf $(CHECK_RESULTS) && mkdir -p $(CHECK_RESULTS)
	$(run_be_checks)
	$(summarize_checks)

# Frontend checks only (CI runs this in the frontend job — no DB needed).
fe_check_all:
	@rm -rf $(CHECK_RESULTS) && mkdir -p $(CHECK_RESULTS)
	$(run_fe_checks)
	$(summarize_checks)

# Everything in one pass (local convenience). Never short-circuits: the run_* batches capture each
# exit code into <name>.status, so failures are reported by summarize_checks, not by aborting early.
check_all:
	@rm -rf $(CHECK_RESULTS) && mkdir -p $(CHECK_RESULTS)
	$(run_be_checks)
	$(run_fe_checks)
	$(summarize_checks)

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

# Run Rails tests (full suite → coverage floor applies unless gated off; lock prevents overlapping suite runs)
rails-test:
	$(RAILS_TEST_COV_ENV) $(TEST_LOCK) bundle exec rails test

# Run frontend tests (Vitest, node-only — no backend). Runs inside the web container; also part of check_all.
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
	@test -f .env.development || (cp .env.example .env.development && echo "Created .env.development from .env.example")
	@test -f test/playwright/helpers/.env || (cp test/playwright/helpers/.env.example test/playwright/helpers/.env && echo "Created test/playwright/helpers/.env")

# Point git at the repo's hooks, so commits get their DCO sign-off automatically
git-hooks:
	@git config core.hooksPath .githooks
	@echo "core.hooksPath -> .githooks (commits are signed off automatically)"

# First-time setup: build images, install deps, prepare database
setup: ensure-env git-hooks
	$(DOCKER_COMPOSE) build
	$(DOCKER_COMPOSE) run --rm web echo "Setup complete"
	@make build-agents

# Start all services
up: ensure-env
	$(DOCKER_COMPOSE) up

down:
	$(DOCKER_COMPOSE) down

reset:
	$(DOCKER_COMPOSE) down -v

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

# Build agent images (core first, then agents in parallel).
#
# A bare `wait` returns 0 even when a child build failed, which silently shipped a broken
# image (seen 2026-08-05: a network blip killed one agent build and the target stayed green).
# So: collect the PIDs and wait on each one, and fail the target if any of them failed.
build-agents:
	docker build -t aixle/agent-base-core:latest -f docker/base/Dockerfile docker/base
	@pids=""; \
	docker build -t aixle/claude-code:latest -f docker/claude-code/Dockerfile docker/ & pids="$$pids $$!"; \
	docker build -t aixle/cursor-cli:latest -f docker/cursor-cli/Dockerfile docker/ & pids="$$pids $$!"; \
	docker build -t aixle/codex:latest -f docker/codex/Dockerfile docker/ & pids="$$pids $$!"; \
	docker build -t aixle/gemini-cli:latest -f docker/gemini-cli/Dockerfile docker/ & pids="$$pids $$!"; \
	docker build -t aixle/grok:latest -f docker/grok/Dockerfile docker/ & pids="$$pids $$!"; \
	fail=0; for p in $$pids; do wait $$p || fail=1; done; \
	if [ $$fail -ne 0 ]; then echo "ERROR: at least one agent image failed to build"; exit 1; fi

# Help command
help:
	@echo "Available commands:"
	@echo "  make setup                  - Build images and install all dependencies (first-time setup)"
	@echo "  make up                     - Start all services (web, worker, db, redis, temporal, ...)"
	@echo "  make down                   - Stop all containers"
	@echo "  make reset                  - Stop containers and remove volumes (destructive)"
	@echo "  make worker                 - Start worker only"
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
	@echo "  make git-hooks              - Enable the repo's git hooks (auto DCO sign-off)"
	@echo "  make db_restore_remote      - Restore database remotely"
	@echo "  make restore-dump           - Restore a locally available database dump"
	@echo "  make default                - Same as 'check'"
	@echo "  make help                   - Show this help message"
	@echo "  make shell                  - Open shell in web container"
	@echo ""
	@echo "Agent Docker Images:"
	@echo "  make build-agents           - Build all agent images (core + 4 agents in parallel)"
	@echo "  make build-otlp-ingest      - Build the OTLP ingest image"
