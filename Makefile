# Application Management
.PHONY: deps db-prepare db-reset check check_all be_check_all fe_check_all lint_check_all system_check_all rails_check_all vitest_check_all coverage_merge be_check fe_check lint fix secret-scan typescript test rails-test fe-test worker-boot rubocop rubocop-fix eslint eslint-fix fsd fsd-fix db_restore brakeman license-report license-report-ruby license-report-js default setup git-hooks up down reset worker shell build-web build-otlp-ingest build-agents restore-dump help

DOCKER_COMPOSE ?= docker compose

# docker-compose.yml runs web and worker as this user, so files they write into
# the checkout stay owned by it on a Linux host. Docker Desktop and OrbStack do
# not map ownership, and hand containers the socket as root's group.
export UID := $(shell id -u)
export GID := $(shell id -g)
ifeq ($(shell uname -s),Linux)
export DOCKER_GID ?= $(shell stat -c %g /var/run/docker.sock 2>/dev/null || echo 0)
endif

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
# The gate: what CI runs, and it changes nothing. `make fix` is the autocorrecting pass.
check: check_all

# CI checks. bin/run-check writes tmp/check_results/<name>.log, .status and .seconds, so a batch
# never short-circuits and every failure is surfaced together. `check_all` is the one-command run
# for local use. CI runs the same checks split into jobs (see .github/workflows/ci.yml): lint,
# system, the Rails suite and Vitest each in shards, and a coverage job that merges the shards'
# results and enforces both floors.
CHECK_RESULTS := tmp/check_results
export CHECK_RESULTS

# Backend coverage floor, enforced only on full-suite runs (see test/test_helper.rb).
# Ratchet upward as coverage grows — never lower it. Measured 88.3% on 2026-07-06.
COVERAGE_MIN := 85

# Coverage gating (task #288). CI measures coverage on every run, pull requests
# included, so a drop below a floor fails the review rather than the merged commit;
# it forwards the flag into the container as RUN_COVERAGE (see code-check.yml /
# docker-compose.ci.yml). RUN_COVERAGE=0 skips the instrumentation (SimpleCov and
# v8 over the whole frontend are a large runtime multiplier) for a quick local run. Unset/empty
# (local `make check_all`/`rails-test`) means 1, the same gate CI applies.
RUN_COVERAGE ?= 1
ifeq ($(strip $(RUN_COVERAGE)),)
  RUN_COVERAGE := 1
endif

# CI shards. TOTAL_SHARDS / FE_TOTAL_SHARDS of 1, the default, run the whole suite. A shard
# measures coverage for part of the suite, so it enforces no floor; it leaves its raw result in
# coverage/shards/ and `coverage_merge` applies the floors to the merged whole.
SHARD           ?= 1
TOTAL_SHARDS    ?= 1
FE_SHARD        ?= 1
FE_TOTAL_SHARDS ?= 1
COVERAGE_SHARDS := coverage/shards

ifeq ($(strip $(TOTAL_SHARDS)),1)
  RAILS_TEST_CMD := bundle exec rails test
else
  RAILS_TEST_CMD := bin/rails-test-shard $(SHARD) $(TOTAL_SHARDS)
endif

ifeq ($(strip $(RUN_COVERAGE)),1)
  ifeq ($(strip $(TOTAL_SHARDS)),1)
    # Enforce the backend floor and produce a coverage report.
    RAILS_TEST_COV_ENV := COVERAGE_MIN=$(COVERAGE_MIN)
  endif
  # Frontend: run Vitest with v8 coverage + thresholds (vitest.config.ts).
  FE_TEST_CMD := yarn test --coverage
else
  # Skip SimpleCov instrumentation entirely (test_helper.rb honors SKIP_COVERAGE).
  RAILS_TEST_COV_ENV := SKIP_COVERAGE=1
  # Frontend: run Vitest without coverage instrumentation/thresholds.
  FE_TEST_CMD := yarn test
endif

ifneq ($(strip $(FE_TOTAL_SHARDS)),1)
  # The blob carries the shard's test results and raw coverage for `vitest --merge-reports`.
  FE_TEST_CMD += --shard=$(FE_SHARD)/$(FE_TOTAL_SHARDS) --reporter=default --reporter=blob \
    --outputFile.blob=$(COVERAGE_SHARDS)/vitest/$(FE_SHARD)-$(FE_TOTAL_SHARDS).json
  ifeq ($(strip $(RUN_COVERAGE)),1)
    # coverage-v8 checks thresholds in every run that has them, and a shard covers only part
    # of the suite.
    FE_TEST_CMD += --coverage.reporter=text-summary --coverage.thresholds.lines=0 \
      --coverage.thresholds.statements=0 --coverage.thresholds.branches=0 --coverage.thresholds.functions=0
  endif
endif

# Two concurrent `rails test` invocations are mutually destructive: parallel test
# workers drop/recreate the shared aixle_test_N databases, so overlapping runs
# corrupt each other's schemas (observed 2026-07-03: pg_class duplicate-key storms).
# flock serializes make-driven suite runs (BusyBox flock: blocking exclusive lock,
# no timeout flag); runs started outside make must still never overlap — coordinate
# agent sessions working in the same checkout/worktrees.
TEST_LOCK := flock tmp/.rails-test.lock

RAILS_TEST   = bin/run-check rails-test env $(RAILS_TEST_COV_ENV) $(TEST_LOCK) $(RAILS_TEST_CMD)
# VITE_RUBY_PORT: system tests must use the assets built by run_vite_build, and vite_ruby
# picks between built and dev by probing the dev-server port. In a development container
# the dev server is up, wins the probe, and the page is served dev tags (/@vite/client,
# raw application.tsx) the test server cannot deliver — the SPA never mounts and every
# spec fails "Unable to find field Email". Point the probe at a port nothing listens on.
SYSTEM_TEST  = bin/run-check system-test env SKIP_COVERAGE=1 VITE_RUBY_PORT=59999 $(TEST_LOCK) bundle exec rails test:system
RUBOCOP      = bin/run-check rubocop bundle exec rubocop
BRAKEMAN     = bin/run-check brakeman bundle exec brakeman -q -z --no-pager --skip-files public/
ESLINT       = bin/run-check eslint yarn lint
TYPESCRIPT   = bin/run-check typescript yarn tsc
FSD          = bin/run-check fsd yarn fsd
WATCHER_TEST = bin/run-check watcher-test node --test docker/base/watcher/test/*.test.js
FE_TEST      = bin/run-check fe-test $(FE_TEST_CMD)

# Test-mode Vite assets, required before any Rails test: the test env uses built assets and
# autoBuild is off.
# VITE_RUBY_MODE=test selects the vite-test publicOutputDir (a bare `--mode test` only sets
# Vite's JS mode, NOT ViteRuby's output dir → it'd build to vite-dev). --force so a stale
# last-compilation digest never skips the build (leaving no manifest).
# env -u VITE_RUBY_ASSET_HOST -u ASSET_HOST: the deploy image bakes ASSET_HOST=
# https://static.flow.aixle.com into VITE_RUBY_ASSET_HOST (Dockerfile ENV), which Vite would
# otherwise stamp as the base of every dynamic-import chunk URL. On CI the browser then fetches
# chunks from the CDN (which has no freshly-built test chunks) → 404 → the React SPA never
# mounts → system tests fail "Unable to find field Email". Unset it so test chunks resolve
# relative to the Capybara test server.
define run_vite_build
	@echo "Building test-mode Vite assets..."
	@bin/run-check vite-build env -u VITE_RUBY_ASSET_HOST -u ASSET_HOST VITE_RUBY_MODE=test bin/vite build --force
endef

# Sequential, not part of a parallel batch: the worker smoke boots Rails against the test database
# and the tools registry reconciles on boot, so racing it against a suite writing the same database
# buys a few seconds and a class of flake.
define run_boot_checks
	@echo "Running the worker boot smoke (nothing else in the repo ever loads bin/temporal_worker)..."
	@bin/run-check worker-boot bin/worker_boot_check
	@echo "Checking that every file eager-loads (CI's test env eager-loads, a local one does not)..."
	@bin/run-check zeitwerk bin/rails zeitwerk:check
endef

# Backend (Ruby) checks, in parallel. DB-touching runs are serialized by flock.
define run_be_checks
	$(run_vite_build)
	$(run_boot_checks)
	@echo "Running rails-test, rubocop, brakeman, system-test in parallel (DB-touching runs serialized by flock)..."
	@$(RAILS_TEST) & $(SYSTEM_TEST) & $(RUBOCOP) & $(BRAKEMAN) & wait
endef

# Frontend (JS/TS) checks. eslint + tsc run in parallel; Vitest then runs ON ITS OWN. Vitest spawns a
# worker per core and (with coverage on) instruments the whole frontend, so racing it against
# tsc/eslint — let alone the Ruby suite in the old all-in-one check_all — CPU-starved the heaviest
# jsdom+userEvent form tests past their timeout: green in isolation, flaky only under the full load.
define run_fe_checks
	@echo "Running eslint, typescript, fsd, watcher-test in parallel..."
	@$(ESLINT) & $(TYPESCRIPT) & $(FSD) & $(WATCHER_TEST) & wait
	@echo "Running fe-test (Vitest$(if $(filter 1,$(RUN_COVERAGE)), + coverage,)) on its own..."
	@$(FE_TEST)
endef

# Summarize every tmp/check_results/*.status with its duration, print whichever coverage files
# exist, dump the full log of each failed check, and exit non-zero if any failed.
define summarize_checks
	@echo ""
	@echo "=== Summary ==="
	@fail=0; for f in $(CHECK_RESULTS)/*.status; do \
	  name=$$(basename $$f .status); \
	  status=$$(cat $$f); \
	  secs=$$(cat $(CHECK_RESULTS)/$$name.seconds 2>/dev/null); \
	  if [ "$$status" = "0" ]; then \
	    printf "  [OK]   %-14s %5ss\n" "$$name" "$$secs"; \
	  else \
	    printf "  [FAIL] %-14s %5ss (exit %s)\n" "$$name" "$$secs" "$$status"; \
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
	  if [ "$(TOTAL_SHARDS)" != "1" ]; then \
	    stale=" (shard $(SHARD)/$(TOTAL_SHARDS) only — the coverage job reports the merged total)"; \
	  fi; \
	  printf "  backend  (rails / simplecov): %s%%%s\n" "$$be" "$$stale"; \
	fi; \
	if [ -f coverage/frontend/coverage-summary.json ]; then \
	  fe=$$(ruby -rjson -e 'begin; puts JSON.parse(File.read("coverage/frontend/coverage-summary.json"))["total"]["lines"]["pct"]; rescue; puts "n/a"; end' 2>/dev/null); \
	  printf "  frontend (vitest / v8):       %s%%\n" "$$fe"; \
	fi; \
	if [ ! -f coverage/.last_run.json ] && [ ! -f coverage/frontend/coverage-summary.json ]; then \
	  printf "  (none — RUN_COVERAGE=0, or a shard: the coverage job reports the merged total)\n"; \
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

# Backend checks only.
be_check_all:
	@rm -rf $(CHECK_RESULTS) && mkdir -p $(CHECK_RESULTS)
	$(run_be_checks)
	$(summarize_checks)

# Frontend checks only — no DB needed.
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

# CI's lint job: every static check at once, no database.
lint_check_all:
	@rm -rf $(CHECK_RESULTS) && mkdir -p $(CHECK_RESULTS)
	@echo "Running rubocop, brakeman, eslint, typescript, fsd, watcher-test in parallel..."
	@$(RUBOCOP) & $(BRAKEMAN) & $(ESLINT) & $(TYPESCRIPT) & $(FSD) & $(WATCHER_TEST) & wait
	$(summarize_checks)

# CI's system job: the boot checks and the system suite.
system_check_all:
	@rm -rf $(CHECK_RESULTS) && mkdir -p $(CHECK_RESULTS)
	$(run_vite_build)
	$(run_boot_checks)
	@echo "Running system-test..."
	@$(SYSTEM_TEST)
	$(summarize_checks)

# CI's Rails job: shard SHARD of TOTAL_SHARDS of the Rails suite.
rails_check_all:
	@rm -rf $(CHECK_RESULTS) && mkdir -p $(CHECK_RESULTS)
	$(run_vite_build)
	@echo "Running rails-test (shard $(SHARD)/$(TOTAL_SHARDS))..."
	@$(RAILS_TEST)
	@if [ "$(RUN_COVERAGE)" = "1" ] && [ "$(TOTAL_SHARDS)" != "1" ] && [ -f coverage/.resultset.json ]; then \
	  mkdir -p $(COVERAGE_SHARDS)/rails && \
	  cp coverage/.resultset.json $(COVERAGE_SHARDS)/rails/$(SHARD)-$(TOTAL_SHARDS).json; \
	fi
	$(summarize_checks)

# CI's Vitest job: shard FE_SHARD of FE_TOTAL_SHARDS of the frontend suite.
vitest_check_all:
	@rm -rf $(CHECK_RESULTS) && mkdir -p $(CHECK_RESULTS)
	@echo "Running fe-test (shard $(FE_SHARD)/$(FE_TOTAL_SHARDS))..."
	@$(FE_TEST)
	$(summarize_checks)

# CI's coverage job: merges the shards' results under coverage/shards/ into the reports an
# unsharded run writes, and enforces both floors on the merged totals.
coverage_merge:
	@rm -rf $(CHECK_RESULTS) && mkdir -p $(CHECK_RESULTS)
	@bin/run-check coverage-backend env COVERAGE_MIN=$(COVERAGE_MIN) bundle exec bin/collate-coverage $(COVERAGE_SHARDS)/rails
	@bin/run-check coverage-frontend yarn test --merge-reports=$(COVERAGE_SHARDS)/vitest --coverage
	$(summarize_checks)

# Run backend checks
be_check: rails-test rubocop brakeman

# Run frontend checks
fe_check: eslint typescript fsd fe-test

# Run all linters
lint: eslint rubocop brakeman typescript

# Autocorrect what the linters can fix themselves
fix: rubocop-fix eslint-fix fsd-fix

# The secret scan CI runs (.github/workflows/ci.yml). Runs on the host: it needs Docker.
secret-scan:
	docker run --rm -v "$$PWD:/repo" -w /repo ghcr.io/gitleaks/gitleaks:v8.30.1 \
	  git /repo --config /repo/.gitleaks.toml --redact --no-banner

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

# Boot bin/temporal_worker far enough to prove it can start (see the script header).
# Part of be_check_all; standalone here for a quick local check after touching the worker.
worker-boot:
	bin/worker_boot_check

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

# Run the Feature-Sliced Design check (config: steiger.config.js)
fsd:
	yarn fsd

# Run the Feature-Sliced Design check with auto-correction
fsd-fix:
	yarn fsd:fix

# Replaces the LOCAL development database with /db_dumps/latest.sql.gz. It drops the
# database first — and marks it development to get past Rails' guard — so it refuses
# any target but the Compose `db` service.
db_restore:
	@[ "$${RAILS_ENV:-development}" = "development" ] && [ "$(DB_HOST)" = "db" ] || \
	  { echo "db_restore only restores into the local development database (DB_HOST=db)"; exit 1; }
	bundle exec rails db:environment:set RAILS_ENV=development
	bundle exec rails db:drop db:create
	gunzip < /db_dumps/latest.sql.gz | psql -h ${DB_HOST} -U ${DB_USERNAME} ${DB_NAME}
	bundle exec rails db:migrate

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

# The seeded super admin's password is generated here rather than copied: the
# example's placeholder would otherwise be every checkout's admin password.
ensure-env:
	@test -f .env.development || ( \
	  pw=$$(LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c 32); \
	  sed "s/^ADMIN_PASSWORD=replace_with_strong_password$$/ADMIN_PASSWORD=$$pw/" .env.example > .env.development && \
	  echo "Created .env.development from .env.example (ADMIN_PASSWORD generated)")
	@# Compose reads `.env` and nothing else. UID/GID are shell variables, so the
	@# export above reaches compose only through make — a bare `docker compose`,
	@# which is how CLAUDE.md says to run tests and migrations, would fall back to
	@# 1000:1000 and write files owned by nobody in particular. Appended rather
	@# than written: a worktree stack keeps its own overrides in this file.
	@grep -qs '^UID=' .env || ( \
	  printf 'UID=%s\nGID=%s\n' "$(UID)" "$(GID)" >> .env && \
	  echo "Added UID=$(UID) GID=$(GID) to .env (so plain docker compose matches make)")

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

# Build agent images (core first, then every runtime in config/agent_runtimes.json).
build-agents:
	bin/build-agent-images

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
	@echo "  make check                  - The gate: every check CI runs, nothing autocorrected (= check_all)"
	@echo "  make check_all              - Run all checks in parallel, summarize failures at the end"
	@echo "  make lint                   - Run all linters (rubocop, eslint, brakeman, tsc), no autocorrect"
	@echo "  make fix                    - Autocorrect: rubocop -a, eslint --fix, steiger --fix"
	@echo "  make test                   - Run all tests"
	@echo "  make rails-test             - Run Rails tests"
	@echo "  make fe-test                - Run frontend tests"
	@echo "  make rubocop                - Run Rubocop"
	@echo "  make rubocop-fix            - Run Rubocop with auto-correction"
	@echo "  make eslint                 - Run ESLint"
	@echo "  make eslint-fix             - Run ESLint with auto-correction"
	@echo "  make fsd                    - Run the Feature-Sliced Design check (steiger)"
	@echo "  make fsd-fix                - Run the Feature-Sliced Design check with auto-correction"
	@echo "  make typescript             - Run TypeScript compiler check"
	@echo "  make brakeman               - Run Brakeman security analysis"
	@echo "  make license-report         - Generate Ruby and npm license reports"
	@echo "  make license-report-ruby    - Generate Ruby gem license report"
	@echo "  make license-report-js      - Generate npm production license report"
	@echo "  make git-hooks              - Enable the repo's git hooks (auto DCO sign-off)"
	@echo "  make restore-dump           - Restore a locally available database dump"
	@echo "  make default                - Same as 'check'"
	@echo "  make help                   - Show this help message"
	@echo "  make shell                  - Open shell in web container"
	@echo ""
	@echo "Agent Docker Images:"
	@echo "  make build-agents           - Build all agent images (core + every runtime in config/agent_runtimes.json)"
	@echo "  make build-otlp-ingest      - Build the OTLP ingest image"
