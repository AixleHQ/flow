# AI Planning & Architecture — Directory Index

**Project:** Aixle
**Last Updated:** 2026-07-05

Keep this index in sync: whenever a document is added to or removed from `ai/`, update the corresponding entry here (see CLAUDE.md).

---

## Core Documents

- **[project-overview.md](./project-overview.md)** — Executive summary, tech stack, architecture overview, data model, API structure
- **[project-context.md](./project-context.md)** — LLM-optimized rules: tech stack, patterns, anti-patterns, key file locations

## Architecture

- **[architecture/index.md](./architecture/index.md)** — Architecture Decision Document: strategies, runtimes, adapters, workflows, multi-tenancy
- **[architecture/core-architectural-decisions.md](./architecture/core-architectural-decisions.md)** — Data, auth, API, frontend, infra decisions, trade-offs
- **[architecture/implementation-patterns-consistency-rules.md](./architecture/implementation-patterns-consistency-rules.md)** — Naming, structure, API controllers, authorization, anti-patterns
- **[architecture/workflow-system.md](./architecture/workflow-system.md)** — Workflow engine and execution flow
- **[architecture/temporal-error-handling.md](./architecture/temporal-error-handling.md)** — Temporal error classification and retry strategy
- **[architecture/container-runtime-k8s-pods.md](./architecture/container-runtime-k8s-pods.md)** — Kubernetes Pod runtime implementation
- **[architecture/container-service-refactoring-v2.md](./architecture/container-service-refactoring-v2.md)** — ContainerService phase-based refactoring (historical record)

## System Design

- **[workflow-architecture.md](./workflow-architecture.md)** — Workflow engine data models
- **[tool-execution-framework.md](./tool-execution-framework.md)** — Tool execution strategy framework
- **[session-config-cascade.md](./session-config-cascade.md)** — Session config resolution cascade
- **[session-context-constructor.md](./session-context-constructor.md)** — Unified session context constructor
- **[meta-workflow-design.md](./meta-workflow-design.md)** — Meta-workflow design
- **[system-workflow-bmad-integration.md](./system-workflow-bmad-integration.md)** — System workflows + BMAD integration
- **[bmad-method-checkbox-integration.md](./bmad-method-checkbox-integration.md)** — BMAD toggle in session config
- **[BMAD-structure-description.md](./BMAD-structure-description.md)** — BMAD-METHOD framework layout (external reference)

## Feature Pipeline

The active workflow: a research report in `research/` feeds a frozen-intent spec in `specs/`, which drives implementation.

- **[research/](./research/)** — Technical research reports + settled design docs, paired per topic (`<topic>-research-<date>.md` + `<topic>-<date>.md`)
- **[specs/](./specs/)** — Feature specs: frontmatter (`type`, `created`, `baseline_commit`, `status`, `context`) + Intent / Boundaries / I/O matrix / Tasks / Verification

## Related documentation elsewhere

- `references/aixle-system-reference.md` — agent-facing platform reference (domain model, runtimes, container layout)
- `app/frontend/pages/Docs/data/pages/` — end-user product docs rendered in the app
- `docs/` — product/business strategy documents
