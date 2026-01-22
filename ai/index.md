# Palad Project Documentation Index

**Last Updated:** 2026-01-21
**Purpose:** This index provides an overview of all planning and architecture documents in the `ai/` directory.

---

## Core Planning Documents

### `prd.md`
**Product Requirements Document** — Comprehensive product specification with functional and non-functional requirements, user journeys, and project scope. Generated through BMAD Method PRD workflow. Contains 53 functional requirements across 9 categories and 15 non-functional requirements.

**Status:** ✅ Complete
**Workflow:** PRD workflow (14 steps completed)

---

### `architecture.md`
**Architecture Decision Document** — Complete architectural decisions for the Palad project. Includes technology stack choices, implementation patterns, project structure, and validation results. This is the primary reference for all architectural decisions during implementation.

**Status:** ✅ Complete
**Workflow:** Create Architecture workflow (8 steps completed)
**Key Sections:**
- Project Context Analysis
- Core Architectural Decisions (Data, Auth/Security, API/Communication, Frontend, Infrastructure)
- Implementation Patterns & Consistency Rules
- Project Structure & Boundaries
- Architecture Validation Results

---

### `project-context.md`
**Project Context for AI Agents** — Critical implementation rules and patterns that AI agents must follow when writing code. Optimized for LLM context efficiency, focusing on unobvious details that agents might miss.

**Status:** ✅ Complete
**Workflow:** Generate Project Context workflow
**Key Sections:**
- Technology Stack & Versions
- Language-Specific Rules (TypeScript, Ruby)
- Framework-Specific Rules (React, Rails, RTK Query)
- Testing Rules
- Code Quality & Style Rules
- Critical Don't-Miss Rules (Anti-patterns, Edge Cases, Security)

---

### `ux-design-specification.md`
**UX Design Specification** — Complete user experience design specification including user personas, design challenges, core UX principles, visual design guidelines, and detailed user journey flows.

**Status:** ✅ Complete
**Workflow:** Create UX Design workflow (14 steps completed)

---

## Architecture Documents

### `architecture-web.md`
**Web Part Architecture** — Detailed architecture documentation for the Rails + React web application. Describes technology stack, directory structure, and architectural patterns for the backend and frontend components.

**Status:** ✅ Complete
**Part:** web (Rails 8 + React 19)

---

### `architecture-ai-engine.md`
**AI Engine Part Architecture** — Architecture documentation for the Python AI Engine component. Describes LangGraph/LangChain integration, Qdrant vector database, and Temporal worker patterns.

**Status:** 🔄 Legacy (migrated from previous product)
**Part:** ai-engine (Python 3.13)

---

### `integration-architecture.md`
**Integration Architecture** — Documentation of how Ruby and Python components integrate via Temporal orchestration. Includes communication patterns, workflow diagrams, and cross-language integration points.

**Status:** ✅ Complete

---

## Planning & Discovery Documents

### `project-overview.md`
**Project Overview** — High-level project summary generated from project scan. Includes project classification, parts summary, technology stack overview, and key capabilities.

**Status:** ✅ Complete
**Workflow:** document-project workflow

---

### `brainstorm-palad-platform.md`
**Brainstorm: Palad Platform** — Architectural brainstorming session covering platform vision, architectural decisions, session lifecycle, container architecture, and data model ideas.

**Status:** ✅ Complete
**Date:** 2026-01-20

---

### `brainstorm-bmad-db-config.md`
**Brainstorm: BMad Configuration in Database** — Exploration of moving BMad Method configuration from file system to database for better multi-tenancy, persistence, and versioning.

**Status:** Draft
**Date:** 2026-01-21

---

### `design-thinking-2026-01-15.md`
**Design Thinking Session** — Design thinking workshop output covering the design challenge, user personas, ideation, and solution concepts for the cloud AI agent platform.

**Status:** ✅ Complete
**Date:** 2026-01-15

---

## Technical Design Documents

### `tech-design-xterm-docker-claude-code.md`
**Technical Design: xterm.js + Docker + Claude Code** — Technical design document for implementing interactive terminal in browser connected to Docker containers with Claude Code CLI. Includes implementation status and architecture decisions.

**Status:** ✅ Implemented (with modifications)
**Date:** 2026-01-16
**Last Updated:** 2026-01-20

---

## Development & Operations

### `development-guide.md`
**Development Guide** — Developer onboarding guide with prerequisites, quick start instructions, development workflow, and operational procedures.

**Status:** ✅ Complete
**Generated:** 2026-01-20

---

### `bmm-workflow-status.yaml`
**BMAD Method Workflow Status** — Tracks progress through BMM methodology phases (Analysis, Planning, Solutioning). Shows which workflows are completed, required, or optional.

**Status:** Active tracking
**Generated:** 2026-01-20
**Current Phase:** Solutioning (Architecture complete, Epics/Stories pending)

---

## Analysis & Reports

### `source-tree-analysis.md`
**Source Tree Analysis** — Analysis of project source code structure, organization patterns, and codebase characteristics.

**Status:** ✅ Complete

---

### `project-scan-report.json`
**Project Scan Report** — Machine-readable JSON report from automated project scanning, containing project metadata, dependencies, and structure information.

**Status:** ✅ Complete

---

## UI/UX Assets

### `ux-design-mockup.html`
**UX Design Mockup** — Interactive HTML mockup/prototype of the user interface design. Visual representation of the UX design specification.

**Status:** ✅ Complete

---

## BMAD Method Framework

### `BMAD-METHOD/`
**BMAD Method Framework** — Complete BMAD (Build Method for AI Development) framework source code, documentation, and tools. This is the methodology framework used for project planning and development.

**Note:** This is a submodule/framework directory, not project-specific documentation.

---

## Document Relationships

```
prd.md
  ├── Used by: architecture.md, ux-design-specification.md
  └── Inputs: brainstorm-palad-platform.md, project-overview.md

architecture.md
  ├── Uses: prd.md, ux-design-specification.md, architecture-web.md, architecture-ai-engine.md
  └── Used by: project-context.md (for implementation rules)

project-context.md
  ├── Uses: architecture.md (for patterns and decisions)
  └── Used by: AI agents during implementation

ux-design-specification.md
  ├── Uses: prd.md, project-overview.md
  └── Used by: architecture.md (for frontend decisions)

integration-architecture.md
  ├── Uses: architecture-web.md, architecture-ai-engine.md
  └── Describes: Temporal orchestration patterns
```

---

## Workflow Status

**Completed Workflows:**
- ✅ Document Project (`document-project`)
- ✅ Brainstorm Project (`brainstorm-project`)
- ✅ Create PRD (`prd`)
- ✅ Create UX Design (`create-ux-design`)
- ✅ Create Architecture (`create-architecture`)
- ✅ Generate Project Context (`generate-project-context`)

**Pending Workflows:**
- ⏳ Create Epics and Stories (`create-epics-and-stories`)
- ⏳ Implementation Readiness Review (`implementation-readiness`)
- ⏳ Sprint Planning (`sprint-planning`)

---

## Quick Reference

**For AI Agents:**
- Start with `project-context.md` for implementation rules
- Reference `architecture.md` for architectural decisions
- Check `prd.md` for requirements understanding

**For Developers:**
- Read `development-guide.md` for setup
- Review `architecture-web.md` and `integration-architecture.md` for technical details
- Check `bmm-workflow-status.yaml` for project status

**For Product/Design:**
- Review `prd.md` for requirements
- Check `ux-design-specification.md` for design guidelines
- Reference `ux-design-mockup.html` for visual design

---

**Maintained by:** Artem_petrov
**Last Review:** 2026-01-21
