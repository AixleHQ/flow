# Architecture

A high-level map of how Aixle Flow is put together, for contributors who want
to find their way around the codebase. For the product story ("why"), see
[`README.md`](README.md).

## The big picture

Aixle Flow is a **team-level control plane for AI coding agents**. A user drops
a card on a board (or hits "Run"); a workflow runs each step as an agent inside
an **isolated container**; the team sees the run, its step-by-step trail, and
its cost.

```
Browser ──Inertia──▶ Rails (web)
                       │
                       ├─ Pundit authorization, AASM state machines
                       ├─ PostgreSQL (data)        Redis (cache / sessions)
                       │
                       └─ Temporal ──▶ ContainerWorkflow
                                          │
                                  Runtime (Docker | Kubernetes)
                                          │
                                  Agent container (Claude Code / Cursor CLI /
                                  Codex / Gemini CLI) — runs in isolation,
                                  streams logs, usage, and cost back
```

## Backend

- **Framework:** Ruby on Rails 8.1.
- **Database:** PostgreSQL via ActiveRecord. Schema in `db/schema.rb`.
- **Cache / sessions:** Redis.
- **Multi-tenancy:** `Company → Project` hierarchy. Resources are scoped (often
  polymorphically by `Company`/`Project`); tenant queries filter by
  `company_id`.
- **State machines:** [AASM](https://github.com/aasm/aasm) in
  `app/state_machines/` — `Company`, `User` (account + onboarding), and
  `TerminalSession` lifecycles.
- **Enums:** the `enumerize` gem (not `ActiveRecord::Enum`) — better scopes and
  i18n.
- **Authentication:** Google OAuth via OmniAuth; cookie/session-based (no JWT).
- **Authorization:** [Pundit](https://github.com/varvet/pundit) policies in
  `app/policies/`, auto-matched to controllers via
  `AuthorizationConcern#dynamic_authorize!`. The policy namespace mirrors the
  controller namespace.
- **Encryption:** `ActiveSupport::MessageEncryptor` for agent credentials,
  integration credentials, and config-item secrets.
- **File storage:** Shrine + S3-compatible storage for asset versions and
  session logs.

## API

- **Style:** REST, JSON. No GraphQL.
- **Conventions:** lists wrapped in `{ items: [...] }`, single records in
  `{ data: {...} }`. Filtering via Ransack, pagination via Pagy.
- **Docs:** OpenAPI auto-generated from controllers (OAS Rails), served at
  `/api-docs`.
- **Case conversion:** snake_case on the wire (Rails), automatically converted
  to/from camelCase in the frontend API client.
- **Real-time:** ActionCable (e.g. terminal/session state updates).
- **MCP:** tools are integrated through the Model Context Protocol.

## Frontend

- **Stack:** React 19 + TypeScript, built with Vite.
- **Server-driven routing:** [Inertia.js](https://inertiajs.com/) — Rails
  controllers render React pages; no separate client-side router or REST
  fetching layer for page navigation.
- **UI:** [Mantine 9](https://mantine.dev/) component library.
- **Local state:** Zustand. Forms use Mantine Form.
- **Organization:** Feature-Sliced Design (`app → pages → features → entities →
  shared`) under `app/frontend/`.

## Container execution

The heart of the platform: running agents and tools safely and reproducibly.

- **Pattern:** **Strategy + Runtime**. *Strategies* define **what** to do;
  *Runtimes* define **where** it runs.
- **Strategies** (`app/services/container_strategies/`):
  - `AgentAuthStrategy` — collect agent OAuth credentials via file-watching
    inside the container;
  - `AgentSessionStrategy` — interactive / non-interactive agent sessions with
    credential injection and log/usage collection;
  - `ToolExecutionStrategy` — run a custom tool with parameters, file mounts,
    and exit-code tracking.
- **Runtimes:**
  - `DockerRuntime` — local Docker daemon (development default);
  - `KubernetesRuntime` — Pods + Services + Traefik IngressRoutes (production
    scaling). Selected via `CONTAINER_RUNTIME`.
- **Lifecycle:** `pull_image → create_container → start_container → exec →
  cleanup`, with `before_/after_` hooks.
- **Orchestration:** [Temporal](https://temporal.io/) — `ContainerWorkflow`
  manages the full container lifecycle, including signals for interactive
  sessions, so long-running runs are durable and retryable.
- **Agent adapters:** one per supported agent (Claude Code, Cursor CLI, Codex,
  Gemini CLI). Each defines auth paths, config generation, and usage/cost
  collection.

## Infrastructure & quality

- **Local dev:** Docker Compose — web (Rails + Vite), Temporal, PostgreSQL,
  Redis. One `make setup` / `make up`.
- **Agent images:** custom Docker images per agent, built from a shared base.
- **Monitoring:** structured JSON logging (Lograge), error tracking (Rollbar),
  Temporal UI for workflow monitoring.
- **CI/CD:** GitHub Actions. Quality gate is `make check_all` — tests, RuboCop,
  Brakeman, ESLint, and TypeScript, run in parallel.

## Key trade-offs

| Decision               | Chosen                | Why                                                  |
| ---------------------- | --------------------- | ---------------------------------------------------- |
| Page rendering         | Inertia.js            | Rails-rendered React; no separate SPA API layer      |
| Orchestration          | Temporal              | Multi-phase container lifecycles need a workflow engine |
| Runtime abstraction    | Strategy + Runtime    | Same strategies on Docker locally and Kubernetes in prod |
| API style              | REST                  | Fits CRUD patterns; standard and simple              |
| Session auth           | Cookie-based          | Internal platform, no external API clients (simpler) |
| Enums                  | `enumerize`           | Scopes + i18n, no DB-level integers                  |

> This document describes the current architecture at a high level. Deeper,
> evolving design notes live alongside the code. If something here drifts from
> the implementation, the code is the source of truth — please open a PR to fix
> the doc.
