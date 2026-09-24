# Architecture

A high-level map of how Aixle Flow is put together, for contributors who want
to find their way around the codebase. For the product story ("why"), see
[`README.md`](README.md); every deeper document is listed in
[`docs/index.md`](docs/index.md).

## The big picture

Aixle Flow is a **team-level control plane for AI coding agents**. A user drops
a card on a board (or hits "Run"); a workflow runs each step as an agent inside
an **isolated container**; the team sees the run, its step-by-step trail, and
its cost.

```
Browser ──Inertia──▶ Rails (web)          Agent containers ──▶ Rails (MCP server)
                       │
                       ├─ Pundit authorization, AASM state machines
                       ├─ PostgreSQL (data, Solid Queue jobs)
                       ├─ Redis (cache, Rack::Attack, Action Cable)
                       │
                       └─ Temporal ──▶ ContainerWorkflow
                                          │
                                  Runtime (Docker locally | Kubernetes in production)
                                          │
                                  Agent container (one of seven agent CLIs) — runs in
                                  isolation, reports logs, usage, and cost back
```

## Backend

- **Framework:** Ruby on Rails 8.1. Exact versions live in `.ruby-version` and
  `Gemfile.lock`.
- **Database:** PostgreSQL via ActiveRecord. Schema in `db/schema.rb`.
  Background jobs run on Solid Queue, also in PostgreSQL.
- **Redis:** the Rails cache, Rack::Attack counters, and the Action Cable
  adapter. Browser sessions are not stored there (see Authentication).
- **Multi-tenancy:** a user belongs to one or more companies through
  `CompanyMembership`; each company owns projects. Resources are scoped
  polymorphically to a `Company` or a `Project`, and tenant queries filter by
  `company_id`. The request's company is the session's active membership
  (`AuthConcern#current_membership`).
- **State machines:** [AASM](https://github.com/aasm/aasm) in
  `app/state_machines/`: `Company`, `CompanyMembership` (membership and
  onboarding), `User` (account), `TerminalSession`, and `WorkflowRun`.
- **Enums:** the `enumerize` gem (not `ActiveRecord::Enum`), for better scopes
  and i18n.
- **Authentication:** email and password, Google OAuth via OmniAuth, and
  sign-up through an invitation. The Rails cookie session points at a
  server-side `UserSession` row, so a sign-in can be ended from the server. No
  JWT. People reach the platform programmatically with a personal MCP token;
  agent containers use per-session keys; inbound webhooks verify their own
  signatures or secrets.
- **Authorization:** [Pundit](https://github.com/varvet/pundit) policies in
  `app/policies/`, matched to controllers by
  `AuthorizationConcern#dynamic_authorize!`. The policy namespace mirrors the
  controller namespace. Roles are per company (`admin`, `employee`, `viewer`);
  the platform super admin is a flag on `User` and works in `/admin`.
- **Encryption:** `ActiveSupport::MessageEncryptor` (the `Encryptable`
  concern) for agent credentials, integration and OAuth credentials,
  config-item secrets, and the other stored secrets.
- **File storage:** Shrine + S3-compatible storage for asset versions, session
  logs, and tool output.

## API

- **Style:** REST and JSON under `/api/v1`, called by the web app on its own
  cookie session (requests other than GET carry the CSRF token). No GraphQL.
- **Responses:** one record is its Alba resource's hash; a list is a bare
  array, with paging in headers (`X-Total-Count`). Errors are
  `{ error: "..." }` or `{ errors: [...] }`. Filtering via Ransack, pagination
  via Pagy.
- **Docs:** OpenAPI generated from the controllers (OAS Rails), served at
  `/api-docs`. Reference: [`docs/reference/api.md`](docs/reference/api.md).
- **Case conversion:** server-side. Incoming params are underscored
  (`ApplicationController#underscore_params`); Alba resources camelize their
  keys, `DeepKeyCamelizer` camelizes every Inertia prop
  (`config/initializers/inertia.rb`), and Typelizer generates camelCase
  TypeScript types from the resources.
- **Real-time:** Inertia Cable signed streams over Action Cable — refresh
  signals and id-only row updates, never record payloads.
- **MCP:** the app is an MCP server (`/mcp` and `/action_mcp`, its own Puma process). Agent
  sessions call it with their session key; people call it with a personal
  MCP token.

## Frontend

- **Stack:** React 19 + TypeScript, built with Vite.
- **Server-driven routing:** [Inertia.js](https://inertiajs.com/) — Rails
  controllers render React pages; there is no client-side router. `ts_routes`
  generates typed route helpers into `app/frontend/shared/routes.ts`.
- **UI:** [Mantine 9](https://mantine.dev/) and Tabler icons.
- **State:** server state arrives as Inertia props; everything else is React
  state and hooks. There is no client-side store.
- **Forms:** Mantine Form with Zod schemas, validated through `zod4Resolver`
  (`mantine-form-zod-resolver`).
- **Organization:** `app/frontend/` holds `pages/` (Inertia pages, grouped by
  product area), `shared/` (`ui`, `components`, `resources`, `lib`, `theme`,
  `analytics`), `layouts/`, and Typelizer's `types/generated/` — a loose
  Feature-Sliced Design checked by steiger (`make fsd`). Conventions:
  [`docs/project/context.md`](docs/project/context.md).

## Container execution

The heart of the platform: running agents and tools safely and reproducibly.

- **Pattern:** **Strategy + Runtime**. *Strategies* define **what** to do;
  *Runtimes* define **where** it runs.
- **Strategies** (`app/services/container_strategies/`):
  - `AgentAuthStrategy` — capture an agent CLI's login by watching its
    credential files inside the container;
  - `AgentSessionStrategy` — interactive / non-interactive agent sessions with
    credential injection and log/usage collection (`WorkflowStepStrategy`
    specializes it for workflow steps);
  - `ToolStrategy` — run a tool with parameters, file mounts, and exit-code
    tracking (`CustomToolStrategy`, `InternalToolStrategy`).
- **Runtimes** (`app/services/container_runtime/`), selected by
  `CONTAINER_RUNTIME`:
  - `DockerRuntime` — the local Docker daemon; the default, used in
    development;
  - `KubernetesRuntime` — Pods + Services + Traefik IngressRoutes; what
    production runs.
- **Lifecycle:** `pull_image → create_container → start_container → exec →
  cleanup`, with `before_/after_` hooks.
- **Orchestration:** [Temporal](https://temporal.io/) — `ContainerWorkflow`
  manages the full container lifecycle, including signals for interactive
  sessions, so long-running runs are durable and retryable;
  `WorkflowExecutionWorkflow` walks a workflow run's steps. Scheduled sweeps
  are declared in `app/temporal/schedules.yml`.
- **Agent adapters:** one per runtime in `app/services/agents/` — Claude Code,
  Cursor CLI, Codex, Gemini CLI, Antigravity CLI, Grok, and Kiro CLI. Each
  defines auth paths, config generation, and usage/cost collection; see
  [`docs/user-guide/runtimes.md`](docs/user-guide/runtimes.md).

## Infrastructure & quality

- **Local dev:** Docker Compose — web (Rails, Vite, and the MCP server),
  worker (Temporal), Temporal and its UI, PostgreSQL, Redis, Traefik, and the
  OTLP ingest relay. `make setup` once, then `make up`.
- **Production:** Kubernetes. The cluster manifests live in a separate
  operations repository; `.github/workflows/images.yml` publishes the web,
  ingest, and agent images.
- **Agent images:** one image per runtime under `docker/`, built from a shared
  base (`make build-agents`).
- **Monitoring:** structured JSON logging (Lograge), error tracking with
  Sentry (backend and browser), and the Temporal UI for workflow runs.
- **CI/CD:** GitHub Actions runs `make be_check_all` and `make fe_check_all`
  as separate jobs, plus a gitleaks secret scan. `make check_all` runs both
  locally — see [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Key trade-offs

| Decision               | Chosen                | Why                                                  |
| ---------------------- | --------------------- | ---------------------------------------------------- |
| Page rendering         | Inertia.js            | Rails-rendered React; no separate SPA API layer      |
| Orchestration          | Temporal              | Multi-phase container lifecycles need a workflow engine |
| Runtime abstraction    | Strategy + Runtime    | Same strategies on Docker locally and Kubernetes in prod |
| API style              | REST                  | Fits CRUD patterns; standard and simple              |
| Browser auth           | Cookie session + `UserSession` row | The web app and its JSON API share one session and CSRF protection; programmatic clients use personal MCP tokens |
| Enums                  | `enumerize`           | Scopes + i18n, no DB-level integers                  |

> This document describes the current architecture at a high level. If
> something here drifts from the implementation, the code is the source of
> truth — please open a PR to fix the doc.
