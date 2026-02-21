# AI Planning & Architecture — Directory Index

**Project:** Palad
**Last Updated:** 2026-02-21

---

## Core Documents

- **[project-overview.md](./project-overview.md)** — Executive summary, tech stack, architecture overview, data model, API structure
- **[project-context.md](./project-context.md)** — LLM-optimized rules: tech stack, patterns, anti-patterns, key file locations
- **[sprint-status.yaml](./sprint-status.yaml)** — Epic/story status tracking
- **[bmm-workflow-status.yaml](./bmm-workflow-status.yaml)** — BMAD workflow execution status

## Architecture

- **[architecture/index.md](./architecture/index.md)** — Architecture Decision Document: strategies, runtimes, adapters, workflows, multi-tenancy
- **[architecture/temporal-error-handling.md](./architecture/temporal-error-handling.md)** — Temporal error classification and retry strategy
- **[architecture/container-execution-framework-epic-8.md](./architecture/container-execution-framework-epic-8.md)** — Strategy Pattern container framework
- **[architecture/container-runtime-k8s-pods.md](./architecture/container-runtime-k8s-pods.md)** — Kubernetes Pod runtime implementation
- **[architecture/container-service-refactoring-v2.md](./architecture/container-service-refactoring-v2.md)** — ContainerService phase-based refactoring
- **[architecture/workflow-system.md](./architecture/workflow-system.md)** — Workflow engine and execution flow
- **[architecture/implementation-patterns-consistency-rules.md](./architecture/implementation-patterns-consistency-rules.md)** — Naming, structure, API controllers, authorization, anti-patterns
- **[architecture/core-architectural-decisions.md](./architecture/core-architectural-decisions.md)** — Data, auth, API, frontend, infra decisions, trade-offs
- **[architecture/project-structure-boundaries.md](./architecture/project-structure-boundaries.md)** — Directory structure, boundaries, data flows, integration points
- **[architecture/architecture-status.md](./architecture/architecture-status.md)** — Implementation progress

## Product Requirements

- **[prd/index.md](./prd/index.md)** — Product Requirements Document (sharded, 12 sections)
- **[ux-design-specification.md](./ux-design-specification.md)** — UI/UX patterns and design specification

## Epics & Stories

- **[epics/index.md](./epics/index.md)** — All epics with stories (1–17)
- **[epics/epic-summary.md](./epics/epic-summary.md)** — Summary across all epics
- **[epic-8-unified-container-architecture.md](./epic-8-unified-container-architecture.md)** — Epic 8: Strategy Pattern framework
- **[epic-8-stories-summary.md](./epic-8-stories-summary.md)** — Epic 8 story deliverables

## Research & Deep Dives

- **[cli_agents_deep_research.md](./cli_agents_deep_research.md)** — CLI agents containerization: auth, MCP, tools, skills, context, cost
- **[cursor-cli-usage-tracking.md](./cursor-cli-usage-tracking.md)** — Cursor CLI usage/billing tracking via MITM
- **[deep-research-otel.md](./deep-research-otel.md)** — OpenTelemetry integration for agent usage tracking
- **[workflow-architecture.md](./workflow-architecture.md)** — Workflow engine data models
- **[brainstorm-bmad-db-config.md](./brainstorm-bmad-db-config.md)** — BMAD configuration in database

## Data

- **[project-scan-report.json](./project-scan-report.json)** — Automated project scan raw data

## Subdirectories

- **[architecture/](./architecture/)** — Architecture decision docs
- **[epics/](./epics/)** — Epic definitions and stories
- **[prd/](./prd/)** — Product requirements shards
- **[BMAD-METHOD/](./BMAD-METHOD/)** — BMAD framework source (reference)
