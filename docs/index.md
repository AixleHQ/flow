# Documentation Index

**Project:** Aixle

All architecture, design, research, and strategy docs live under `docs/`. Whenever
a document is added, removed, or moved here, update this index in the same change
(see CLAUDE.md).

---

## Project

- **[project/overview.md](./project/overview.md)** — Executive summary, tech stack, architecture overview, data model, API structure
- **[project/context.md](./project/context.md)** — LLM-optimized rules: tech stack, patterns, anti-patterns, key file locations

## Architecture

- **[architecture/index.md](./architecture/index.md)** — Architecture Decision Document: strategies, runtimes, adapters, workflows, multi-tenancy
- **[architecture/core-decisions.md](./architecture/core-decisions.md)** — Data, auth, API, frontend, infra decisions and trade-offs
- **[architecture/implementation-patterns.md](./architecture/implementation-patterns.md)** — Naming, structure, API controllers, authorization, anti-patterns
- **[architecture/workflows.md](./architecture/workflows.md)** — Workflow engine: concepts, data models, execution flow, internal tools
- **[architecture/container-runtime.md](./architecture/container-runtime.md)** — Pluggable Docker/K8s runtime + ContainerService refactoring (historical)
- **[architecture/temporal-error-handling.md](./architecture/temporal-error-handling.md)** — Temporal error classification and retry strategy

## System Design

- **[design/tool-execution.md](./design/tool-execution.md)** — Tool execution strategy framework
- **[design/meta-workflow.md](./design/meta-workflow.md)** — Meta-workflow / Aixle Builder design
- **[design/session-config-and-context.md](./design/session-config-and-context.md)** — Session config cascade + context constructor pipeline
- **[design/bmad.md](./design/bmad.md)** — BMAD integration: implemented toggle, system-workflow RFC, and framework reference

## Feature Pipeline

The active workflow: a research report in `research/` feeds a frozen-intent spec in `specs/`, which drives implementation.

- **[research/](./research/)** — Technical research reports + settled design docs, paired per topic (`<topic>-research-<date>.md` + `<topic>-<date>.md`)
- **[specs/](./specs/)** — Feature specs: frontmatter (`type`, `created`, `baseline_commit`, `status`, `context`) + Intent / Boundaries / I/O matrix / Tasks / Verification

## Strategy

- **[strategy/](./strategy/)** — Business / open-source strategy documents

## Related documentation elsewhere

- `references/aixle-system-reference.md` — agent-facing platform reference (domain model, runtimes, container layout)
- `app/frontend/pages/Docs/data/pages/` — end-user product docs rendered in the app
