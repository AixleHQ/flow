# Palad Project Documentation Index

**Generated**: 2026-01-20
**Workflow**: document-project v1.2.0
**Scan Level**: Deep Scan

---

## Project Overview

- **Type**: Multi-Part Monorepo
- **Parts**: 3 (Web, AI Engine, Infrastructure)
- **Primary Languages**: Ruby, Python, TypeScript
- **Architecture**: Event-Driven + Service-Oriented (Temporal)

---

## Quick Reference

### Web Part (`/web`)

| Attribute | Value |
|-----------|-------|
| **Type** | Web + Backend |
| **Framework** | Rails 8.0.2 + React 19 |
| **Root** | `/web` |
| **Entry** | `bin/dev` (dev), `bin/temporal_worker` (worker) |

### AI Engine Part (`/ai-engine`)

| Attribute | Value |
|-----------|-------|
| **Type** | Backend (AI/ML) |
| **Framework** | Python 3.13 + Temporal |
| **Status** | 🔄 Legacy (from previous product) |
| **Root** | `/ai-engine` |

**Note:** Currently a copy from previous product, will be refactored.

### Infrastructure (`/docker`)

| Attribute | Value |
|-----------|-------|
| **Type** | Infrastructure |
| **Tool** | Docker Compose |
| **Root** | `/docker` |

---

## 📋 Planning Artifacts

| Document | Description | Status |
|----------|-------------|--------|
| [PRD](./prd.md) | Product Requirements Document for Palad | ✅ v1.0 |
| [Workflow Status](./bmm-workflow-status.yaml) | BMM workflows status | 🔄 Active |

---

## 🧠 Brainstorms

| Document | Description |
|----------|-------------|
| [Palad Platform](./brainstorm-palad-platform.md) | Architecture of the cloud AI-agent platform with a workflow system |

---

## Generated Documentation

### Architecture

- [Project Overview](./project-overview.md) — Executive summary, classification
- [Architecture - Web](./architecture-web.md) — Rails + React architecture
- [Architecture - AI Engine](./architecture-ai-engine.md) — Python AI architecture
- [Integration Architecture](./integration-architecture.md) — Cross-part communication

### Development

- [Development Guide](./development-guide.md) — Setup, commands, testing
- [Source Tree Analysis](./source-tree-analysis.md) — Directory structure

---

## Existing Documentation

### Knowledge Base (`/kb`)

- [CLAUDE.md](../kb/CLAUDE.md) — Claude Code rules and standards
- [Product Vision](../kb/product/vision.md) — Product concept, Palladium myth
- [Product Architecture](../kb/product/architecture.md) — Technical architecture
- [Weekly Plan](../kb/operations/team-coordination/tracking/weekly-plan.md) — Current tasks

### Part READMEs

- [Web README](../web/README.md) — Rails setup instructions
- [AI Engine README](../ai-engine/README.md) — Python AI system description

### Design Documents

- [Tech Design: xterm + Docker + Claude Code](./tech-design-xterm-docker-claude-code.md)
- [Design Thinking 2026-01-15](./design-thinking-2026-01-15.md)

---

## Getting Started

### Prerequisites

- Docker and Docker Compose
- (Optional) AWS CLI + AWS Vault for remote operations

### Setup

```bash
# Clone and setup
git clone https://github.com/palad-ai/palad-app.git
cd palad-app
make setup

# Start services
make up

# Access
open http://localhost:4000      # Web UI
open http://localhost:8080      # Temporal UI
```

### Common Tasks

| Task | Command |
|------|---------|
| Start all services | `make up` |
| Start workers | `make workers` |
| Shell (Web) | `make shell-web` |
| Shell (AI Engine) | `make shell-ai-engine` |
| Run all checks | `docker-compose run --rm web make check` |

---

## Team

| Role | Owner | Scope |
|------|-------|-------|
| BMAD Method, UI | Artem | web/, workflows UI, prompts |
| AI Engine, Agents | Andrey | ai-engine/, agents, LLM integration |

---

## Related Resources

- **GitHub**: [github.com/palad-ai](https://github.com/palad-ai)
- **BMAD Method**: `/ai/BMAD-METHOD/`
- **Temporal UI**: http://localhost:8080

---

## Document Status

| Document | Status |
|----------|--------|
| project-overview.md | ✅ Generated |
| architecture-web.md | ✅ Generated |
| architecture-ai-engine.md | ✅ Generated |
| integration-architecture.md | ✅ Generated |
| source-tree-analysis.md | ✅ Generated |
| development-guide.md | ✅ Generated |
| index.md | ✅ Generated |
| brainstorm-palad-platform.md | ✅ Generated |
| prd.md | ✅ Generated |
| bmm-workflow-status.yaml | ✅ Active |

---

**Last Updated**: 2026-01-21
