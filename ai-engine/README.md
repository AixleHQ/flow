# Palad AI

Modern AI-powered system for automated code analysis, documentation processing, and specification generation. Built on **FastAPI + Dagster** architecture.

## 🎯 Core Capabilities

- **Asset Processing**: Codebases, documents (PDF/Word), UI screenshots with intelligent analysis
- **Specification Generation**: Automated SRS, user stories, use cases, and technical requirements
- **Artifact Creation**: ERD diagrams, data flows, code reports
- **Semantic Search**: RAG-powered search across all processed content
- **Intelligence API**: Conversational interface for project exploration

## 🏗️ Architecture

**Stack**: FastAPI + Dagster + PostgreSQL + Qdrant + AI Agents

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   FastAPI       │    │    Dagster      │    │   PostgreSQL    │
│   (API :8080)   │◄──►│ (Pipelines :3000)│◄──►│ (Database :5432)│
└─────────────────┘    └─────────────────┘    └─────────────────┘
        │                       │                       │
        ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│     Qdrant      │    │   AI Agents     │    │    Langfuse     │
│ (Vector :6333)  │◄──►│   (LLM Tasks)   │◄──►│ (Monitor :3001) │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

**Processing Flow**: API → Services → Pipelines → Agents → Vector DB

## 🚀 Quick Start

```bash
# Setup
git clone <repository-url>
cd ai-engine
cp env.sample .env
# Edit .env with your OPENAI_API_KEY and ANTHROPIC_API_KEY

# One-command install
make setup
```

**Access Points:**
- API docs: http://localhost:8080/docs
- Dagster UI: http://localhost:3000
- Health: http://localhost:8080/health

**Start:**
```bash
docker-compose up --build
```

Architecture uses separate containers for Dagit, Daemon, and Code Location (worker).

## ⚙️ Development

### Essential Commands

```bash
make help         # Show all commands
make up/down      # Start/stop services
make logs         # View logs
make shell        # Access worker container

make lint/format  # Code quality
make test         # Run tests
make migrate      # Apply DB migrations

make dagster-logs     # Pipeline logs
make dagster-errors   # Recent errors
make qdrant-clean     # Reset vector DB

# Deployment (ECS)
make deploy-qa    # Deploy to QA (build + push + migrate + deploy)
make deploy-prod  # Deploy to production
```

### Workflow

1. `make setup` - One-time setup
2. `make up` - Start all services
3. `make shell` - Enter worker container
4. Make changes → `make lint` → `make test`
5. Monitor pipelines at http://localhost:3000

## 🔧 Configuration

**Required environment variables in `.env`:**

```bash
# LLM APIs (required)
OPENAI_API_KEY=sk-your-key
ANTHROPIC_API_KEY=sk-ant-your-key

# Database
DATABASE_URL=postgresql://postgres:password@postgres:5432/palad_engine
QDRANT_URL=http://qdrant:6333

# Security
GLOBAL_API_KEY=your-global-key
SECRET_KEY=your-secret
```

## 📚 Documentation

- API docs: http://localhost:8080/docs
- Pipeline monitoring: http://localhost:3000
- Architecture: `memo/` directory

## 🐛 Troubleshooting

**Common fixes:**

```bash
# Services won't start
make logs && make restart

# Database issues
make migrate && make dagster-db-create

# Pipeline failures
make dagster-errors && make dagster-logs

# Complete reset
make down && make rebuild && make setup
```

**Requirements**: 4GB+ RAM, Docker, internet for LLM APIs
