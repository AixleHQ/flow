# Palad Project Overview

**Generated**: 2026-01-20
**Workflow**: document-project v1.2.0
**Scan Level**: Deep Scan

---

## Executive Summary

**Palad** is an AI-powered platform for automated code analysis, document processing, and specification generation. The system is built on a **multi-part monorepo** architecture with three main components integrated via **Temporal** workflow orchestration.

### Key capabilities

- **Interactive Agent Sessions** — Docker containers with Claude Code CLI via web terminal
- **Asset Processing** — analysis of codebases, documents (PDF/Word), and images
- **Specification Generation** — automatic generation of SRS, user stories, use cases
- **Semantic Search** — RAG-powered search across all processed content
- **Cross-Language Workflows** — Ruby and Python workers coordinated by Temporal

---

## Project Classification

| Attribute | Value |
|-----------|-------|
| **Project Name** | Palad |
| **Repository Type** | Multi-Part Monorepo |
| **Parts Count** | 3 |
| **Primary Language** | Ruby (Web), Python (AI), TypeScript (Frontend) |
| **Architecture Pattern** | Event-Driven + Service-Oriented |
| **Field Type** | Brownfield (active development) |

---

## Parts Summary

### 1. Web Part (`/web`)

| Attribute | Value |
|-----------|-------|
| **Type** | Web + Backend |
| **Framework** | Ruby on Rails 8.0.2 |
| **Frontend** | React 19 + TypeScript (FSD) |
| **Database** | PostgreSQL 15.3 |
| **Build Tool** | Vite 7.3.1 |

**Responsibilities:**
- REST API for frontend
- Docker container orchestration
- Temporal workflow client
- User authentication (Google OAuth)
- File upload and storage (Shrine + S3)

### 2. AI Engine Part (`/ai-engine`)

| Attribute | Value |
|-----------|-------|
| **Type** | Backend (AI/ML) |
| **Language** | Python 3.13 |
| **Status** | 🔄 Legacy (migrated from previous product) |

**Note:** AI Engine is currently a copy from the previous product. It contains Temporal workers, AI agents, and vector engine code that will be refactored/replaced as Palad architecture evolves. Not the primary focus of current development.

### 3. Infrastructure Part (`/docker`)

| Attribute | Value |
|-----------|-------|
| **Type** | Infrastructure |
| **Tool** | Docker Compose |
| **Services** | Temporal, PostgreSQL, Redis, Qdrant |

**Responsibilities:**
- Development environment
- Claude Code interactive containers
- Service orchestration

---

## Technology Stack Summary

| Category | Technology | Version |
|----------|------------|---------|
| **Backend** | Ruby on Rails | 8.0.2 |
| **AI Engine** | Python | 3.13 |
| **Frontend** | React + TypeScript | 19.0 / 5.9 |
| **Database** | PostgreSQL | 15.3 |
| **Cache** | Redis | 7.2 |
| **Orchestration** | Temporal | 1.29.0 |
| **Vector DB** | Qdrant | latest |
| **Containerization** | Docker Compose | latest |

---

## Quick Start

```bash
# Clone and setup
git clone https://github.com/palad-ai/palad-app.git
cd palad-app
make setup

# Start all services
make up

# Access
open http://localhost:4000      # Web UI
open http://localhost:8080      # Temporal UI
```

---

## Documentation Index

- [Architecture - Web](./architecture-web.md)
- [Architecture - AI Engine](./architecture-ai-engine.md)
- [Integration Architecture](./integration-architecture.md)
- [Development Guide](./development-guide.md)
- [Source Tree Analysis](./source-tree-analysis.md)

---

## Team

| Role | Owner | Scope |
|------|-------|-------|
| BMAD Method, UI | Artem | web/, workflows UI, prompts |
| AI Engine, Agents | Andrey | ai-engine/, agents, LLM integration |

---

## Related Resources

- **Knowledge Base**: `/kb/` — Product vision, architecture, team coordination
- **BMAD Method**: `/ai/BMAD-METHOD/` — Agent prompts and workflows
- **Weekly Plan**: `/kb/operations/team-coordination/tracking/weekly-plan.md`
