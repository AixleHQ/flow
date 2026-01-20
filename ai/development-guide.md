# Development Guide

**Generated**: 2026-01-20
**Project**: Palad

---

## Prerequisites

- **Docker** and **Docker Compose**
- **AWS CLI** + **AWS Vault** (for remote operations)
- **1Password CLI** (for OTP)

---

## Quick Start

```bash
# 1. Clone repository
git clone https://github.com/palad-ai/palad-app.git
cd palad-app

# 2. Full setup (build + deps + db)
make setup

# 3. Start all services
make up

# 4. Open application
open http://localhost:4000
```

---

## Service Ports

| Service | Port | URL |
|---------|------|-----|
| Web (Rails + Vite) | 4000, 4001 | http://localhost:4000 |
| Temporal UI | 8080 | http://localhost:8080 |
| Temporal Server | 7233 | - |
| PostgreSQL | 5432 | - |
| Redis | 6379 | - |
| Claude Code (ttyd) | dynamic | - |
| Claude Code (watcher) | dynamic | - |

---

## Development Commands

### Root Level

```bash
# Full setup
make setup

# Start services
make up

# Start workers (3 Python + 1 Ruby)
make workers

# Shell access
make shell-web          # Rails container
make shell-ai-engine    # Python container

# Help
make help
```

### Web Part (Rails + React)

```bash
# Enter container first
docker-compose run --rm web bash

# Dependencies
make deps               # bundle install + yarn install

# Database
make db-prepare         # create + migrate + seed
make db-reset           # drop + create + migrate + seed

# Linting
make rubocop            # Ruby linting
make rubocop-fix        # Ruby linting with auto-fix
make eslint             # JS/TS linting
make eslint-fix         # JS/TS linting with auto-fix
make typescript         # TypeScript check
make fsd                # Feature-Sliced Design check
make fsd-fix            # FSD with auto-fix
make brakeman           # Security analysis

# Testing
make rails-test         # Rails tests (Minitest)
make fe-test            # Frontend tests (Vitest)
make test               # All tests

# All checks
make check              # lint + test
make be_check           # Backend checks
make fe_check           # Frontend checks
```

### AI Engine Part (Python)

```bash
# Enter container first
docker-compose run --rm worker-python bash

# Dependencies
make deps               # uv sync

# Generate constants
make workflows          # Generate workflow constants

# Linting
make lint               # ruff check
make lint-ruff          # ruff only
make lint-mypy          # mypy type check
make format             # ruff format

# Testing
make test               # pytest (parallel)

# All checks
make check              # lint + test
```

---

## Environment Variables

### Web Part

Create `web/.env`:

```bash
# Rails
RAILS_ENV=development
SECRET_KEY_BASE=your-secret-key

# Database
DB_HOST=db
DB_PORT=5432
DB_USERNAME=postgres
DB_NAME=palad_development

# Redis
REDIS_URL=redis://redis:6379/1

# Temporal
TEMPORAL_ENABLED=true
TEMPORAL_HOST=temporal
TEMPORAL_PORT=7233

# Auth (Google OAuth)
GOOGLE_CLIENT_ID=your-client-id
GOOGLE_CLIENT_SECRET=your-client-secret

# Claude Code
ANTHROPIC_API_KEY=sk-ant-...

# AWS (for S3)
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=us-east-1
```

### AI Engine Part

Create `ai-engine/.env`:

```bash
# Environment
ENVIRONMENT=development

# LLM APIs
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
OPENROUTER_API_KEY=sk-or-...

# Database
DB_HOST=db
DB_PORT=5432
DB_USERNAME=postgres
DB_NAME=palad_development

# Qdrant
QDRANT_URL=http://qdrant:6333

# Temporal
TEMPORAL_HOST=temporal
TEMPORAL_PORT=7233

# Langfuse (optional)
LANGFUSE_ENABLED=false
LANGFUSE_PUBLIC_KEY=...
LANGFUSE_SECRET_KEY=...
```

---

## Docker Compose Profiles

```bash
# Default services (web, db, redis, temporal)
docker-compose up

# With workers
docker-compose --profile worker up

# With Claude Code
docker-compose --profile claude up

# With infrastructure tools
docker-compose --profile infra up
```

---

## Testing

### Rails Tests (Minitest)

```bash
# All tests
docker-compose run --rm web make rails-test

# Specific test file
docker-compose run --rm web bundle exec rails test test/controllers/api/v1/terminal_sessions_controller_test.rb

# Specific test
docker-compose run --rm web bundle exec rails test test/controllers/api/v1/terminal_sessions_controller_test.rb:15
```

### Frontend Tests (Vitest)

```bash
# All tests
docker-compose run --rm web yarn test

# Watch mode
docker-compose run --rm web yarn vitest
```

### Python Tests (Pytest)

```bash
# All tests (parallel)
docker-compose run --rm worker-python make test

# Specific test file
docker-compose run --rm worker-python pytest tests/activities/test_codebase.py

# With coverage
docker-compose run --rm worker-python pytest --cov=app tests/
```

---

## Code Style

### Ruby

- **Style Guide**: Ruby Style Guide
- **Linter**: Rubocop
- **Config**: `web/.rubocop.yml`

### TypeScript/React

- **Style Guide**: Airbnb
- **Linter**: ESLint + Prettier
- **Config**: `web/eslint.config.js`
- **Architecture**: Feature-Sliced Design (FSD)

### Python

- **Style Guide**: PEP 8
- **Linter**: Ruff
- **Type Checker**: MyPy
- **Config**: `ai-engine/pyproject.toml`

---

## Database

### Migrations

```bash
# Create migration
docker-compose run --rm web bundle exec rails generate migration AddFieldToTable field:type

# Run migrations
docker-compose run --rm web bundle exec rails db:migrate

# Rollback
docker-compose run --rm web bundle exec rails db:rollback
```

### Seeds

```bash
# Run seeds
docker-compose run --rm web bundle exec rails db:seed
```

### Dump/Restore

```bash
# Local dump
docker-compose run --rm web make db_dump

# Restore from dump
docker-compose run --rm web make db_restore

# From QA/Prod (requires AWS)
make restore-qa-db PROFILE=palad
make restore-prod-db PROFILE=palad
```

---

## Temporal

### UI

Access Temporal UI at http://localhost:8080

### Workflows

```bash
# List workflows
# Use Temporal UI or tctl

# Start workflow manually
docker-compose run --rm web bundle exec rails runner "
  TemporalService.start_workflow(
    Workflows::AssetCodebaseProcessing,
    { asset_id: 1 }
  )
"
```

### Workers

```bash
# Start Ruby worker
docker-compose --profile worker up worker-ruby

# Start Python workers (3 instances)
docker-compose --profile worker up --scale worker-python=3 worker-python
```

---

## Claude Code Sessions

### Create Session

```bash
# Via API
curl -X POST http://localhost:4000/api/v1/terminal_sessions \
  -H "Content-Type: application/json" \
  -d '{"step_name": "dev"}'
```

### Access Session

1. Get session URL from API response
2. Open `http://localhost:{ttyd_port}` in browser
3. Or use SessionPage in web UI

---

## Remote Operations (AWS)

```bash
# Login to AWS
make login_aws PROFILE=palad

# QA environment
make qa-web-exec PROFILE=palad      # Shell access
make qa-web-logs PROFILE=palad      # View logs
make qa-web-watch-logs PROFILE=palad # Watch logs

# Production environment
make prod-web-exec PROFILE=palad
make prod-web-logs PROFILE=palad
make prod-web-watch-logs PROFILE=palad
```

---

## Troubleshooting

### Docker Issues

```bash
# Rebuild containers
docker-compose build --no-cache

# Clean up
docker-compose down -v
docker system prune -a
```

### Database Issues

```bash
# Reset database
docker-compose run --rm web make db-reset

# Check connection
docker-compose run --rm web bundle exec rails dbconsole
```

### Temporal Issues

```bash
# Check Temporal status
docker-compose logs temporal

# Restart Temporal
docker-compose restart temporal
```

### Python Dependencies

```bash
# Reinstall dependencies
docker-compose run --rm worker-python uv sync --all-groups --frozen

# Clear cache
docker-compose run --rm worker-python rm -rf .venv
```
