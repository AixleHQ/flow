# Application Management
.PHONY: deps db-prepare db-reset check be_check fe_check lint typescript test rails-test fe-test rubocop rubocop-fix eslint eslint-fix fsd fsd-fix db_dump db_restore db_restore_remote brakeman default setup up worker shell build-web build-otlp-ingest build-agents restore-dump help

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
	@make build-agents

# Run all main services
up:
	docker-compose up

# Run worker
worker:
	docker-compose --profile worker up --no-deps worker

# Open shell in web container
shell:
	docker-compose run --rm web bash

# Restore a locally available database dump
restore-dump:
	docker-compose run --rm web make db_restore

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
	@echo "  make restore-dump           - Restore a locally available database dump"
	@echo "  make default                - Same as 'check'"
	@echo "  make help                   - Show this help message"
	@echo "  make up                     - Run all main services"
	@echo "  make worker                 - Run worker (in a separate terminal)"
	@echo ""
	@echo "Agent Docker Images:"
	@echo "  make build-agents           - Build all agent images (core + 4 agents in parallel)"
	@echo "  make build-otlp-ingest      - Build the OTLP ingest image"
