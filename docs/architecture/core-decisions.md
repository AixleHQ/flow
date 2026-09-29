# Core Architectural Decisions

The decisions that shape the codebase, and what each means in practice.
Versions are not repeated here: they live in `.ruby-version`, `Gemfile.lock`,
`package.json`/`yarn.lock`, and `docker-compose.yml`.

---

## Data Architecture

**Database:** PostgreSQL.

**ORM:** ActiveRecord — primary for all operations.

**Multi-tenancy:** Company → Project hierarchy with a polymorphic `scope` (Company/Project) on scoped resources. All tenant queries filter by `company_id`.

**State machines:** AASM gem, in `app/state_machines/`. Five: `Company`, `CompanyMembership` (membership state + onboarding), `User` (account state), `TerminalSession`, `WorkflowRun`.

**Enums:** `enumerize` gem. Never `ActiveRecord::Enum`.

**Encryption:** `ActiveSupport::MessageEncryptor` through the `Encryptable` concern — agent credentials, integration and OAuth credentials, config-item secrets, and the other stored secrets.

**Validation:** Three levels — DB constraints (NOT NULL, FK, unique) → Model validations (Rails) → Service-level business rules.

**Migrations:** Standard Rails migrations. Schema tracked in `db/schema.rb`.

**Caching and jobs:** Redis backs the Rails cache, Rack::Attack, and the Action Cable adapter. Background jobs run on Solid Queue in PostgreSQL. Browser sessions are cookies, not Redis entries (see below).

---

## Authentication & Authorization

**Authentication:** email + password (`has_secure_password`, no Devise), Google OAuth via OmniAuth, and sign-up through an invitation. The Rails cookie store holds the session, and the cookie points at a server-side `UserSession` row, so signing out elsewhere takes effect immediately. No JWT.

**Other principals:** a personal MCP token per user (the `/mcp` endpoint); per-session keys for agent containers (MCP, credential vending, credential write-back, usage ingest); inbound webhooks that verify their own signature or secret (GitHub, GitLab, Azure DevOps, Slack, the generic `/webhooks/in/:slug`); HTTP Basic for `/api-docs` outside development.

**Authorization:** Pundit policies. Auto-matched to controllers via `AuthorizationConcern#dynamic_authorize!`. Policy hierarchy mirrors controller namespace hierarchy. `deny_read_only_mutation!` backs the policies up by refusing writes from read-only members.

**Roles:** per company, on `CompanyMembership`: `admin`, `employee`, `viewer` (read-only). The platform super admin is the `super_admin` flag on `User`, seeded by `db/seeds.rb` and managed from `/admin`; super admins hold no memberships.

**Multi-tenancy auth:** a user can belong to several companies. The request's company is the session's active membership (`AuthConcern#current_membership`: the company switcher's choice, then the last company used, then the oldest membership), re-checked against active memberships on every request. Project access (`Project#accessible_by?`): the project's owner, a company admin, or a project collaborator, each with an active membership in the project's company.

---

## Container Execution Architecture

**Core decision:** Strategy + Runtime pattern. Strategies define WHAT to do, Runtimes define WHERE.

**Strategies:**
- `AgentAuthStrategy` — credential capture via file watching inside the container, while the user completes the CLI's own login
- `AgentSessionStrategy` — interactive/non-interactive agent sessions with credential injection, log/usage collection (`WorkflowStepStrategy` subclasses it for workflow-step sessions)
- `ToolStrategy` — base for tool execution (command, parameters, file mounts, exit code tracking), with `CustomToolStrategy` (user-defined tools) and `InternalToolStrategy` (platform code-source tools) subclasses

**Runtimes:**
- `DockerRuntime` — docker-api gem, local Docker daemon; the default, used for local development
- `KubernetesRuntime` — kubeclient + websocket, Kubernetes Pods + Services + Traefik IngressRoutes; the production runtime

**Phase lifecycle:** `pull_image → create_container → start_container → exec → cleanup` with `before_/after_` hooks.

**Orchestration:** Temporal workflows. `ContainerWorkflow` manages full container lifecycle with signal support for interactive sessions.

**Agent adapters:** Per-runtime credential/config handling in `app/services/agents/`, one per runtime: `ClaudeCodeAdapter`, `CursorCliAdapter`, `CodexAdapter`, `GeminiCliAdapter`, `AntigravityCliAdapter`, `GrokAdapter`, `KiroCliAdapter`. Each defines auth paths, config generation, and where usage comes from (OTLP telemetry, the MITM proxy log, or the CLI's own output).

---

## API Design

**Pattern:** REST API only. No GraphQL.

**Format:** JSON. Each action renders an Alba resource explicitly (`render json: XResource.new(record).to_h`), with an explicit status where it is not 200.

**Response shape:** one record is the resource's hash; a list is a bare array, with paging in headers (`X-Total-Count`). Errors are `{ error: "..." }` or `{ errors: [...] }`. See [Implementation Patterns](./implementation-patterns.md#response-formats).

**Filtering:** Ransack — `Model.ransack(params[:q]).result`.

**Pagination:** Pagy via `PaginationConcern` (`inertia_scroll` for Inertia infinite scroll).

**Documentation:** OAS Rails (auto-generated OpenAPI from controllers), served at `/api-docs`.

**Case conversion:** snake_case in Ruby; camelCase in TS. Done server-side — incoming params are underscored by `ApplicationController#underscore_params`; outgoing, Alba `transform_keys :lower_camel` plus `DeepKeyCamelizer`, which `config/initializers/inertia.rb` installs as Inertia's `prop_transformer`; Typelizer emits camelCase TS types.

**Real-time:** Inertia Cable signed streams only — no custom ActionCable channels. A page that has authorized its viewer renders the signed stream name as a prop, so only that viewer can subscribe. Models send refresh signals (`broadcasts_to`, which reloads the page's props) or, for the session and run lists, id-only row updates (`session_update` / `run_update`); the list fetches those rows back through its own authorized endpoint (`GET /company/sessions/rows`, `GET /company/projects/:id/sessions/rows`), serialized for that viewer. A broadcast never carries a payload, because one message reaches every subscriber and cannot be redacted per viewer. The cable connection refuses anyone without a live sign-in.

**Internal endpoints:** `/api/v1/internal/` — the Traefik ForwardAuth check for container terminals (`ws_auth`) and OTLP usage ingestion. No user-facing Pundit; each authenticates its caller itself (see [API reference](../reference/api.md#authentication)).

---

## Frontend Architecture

**Framework:** React 19 + TypeScript + Vite, rendered through Inertia.js (`@inertiajs/react`).

**Architecture:** Inertia pages under `app/frontend/pages/`, grouped by product area; shared code under `app/frontend/shared/` (`ui`, `components`, `resources`, `lib`, `theme`, `analytics`); the signed-in shell in `app/frontend/layouts/`.

**State management:** server state arrives via Inertia props; local state is React state and hooks. No client-side store.

**Routing:** server-side Rails routes rendered via Inertia; typed route helpers generated by `ts_routes` into `app/frontend/shared/routes.ts`.

**UI:** Mantine 9.

**Forms:** Mantine forms + Zod, validated through `zod4Resolver` (`mantine-form-zod-resolver`).

**API client:** `apiFetch` (`shared/lib/apiFetch.ts`) — thin `fetch` wrapper injecting the CSRF token (from meta tag) + JSON headers. Most reads flow through Inertia props, not an API cache.

---

## Infrastructure

**Development:** Docker Compose — web (Rails + Vite + the MCP server), worker, Temporal, PostgreSQL, Redis, Traefik, OTLP ingest.

**Agent containers:** One Docker image per runtime (`docker/<runtime>/`) built from a shared base image (`docker/base/`).

**Kubernetes:** the production container runtime (Pods + Services + Traefik IngressRoutes), selected with `CONTAINER_RUNTIME`. Cluster manifests and deployment configuration live in a separate operations repository, not in this one.

**File storage:** Shrine + AWS S3 for asset versions, session logs, tool output.

**Monitoring:** Lograge (structured JSON logging), Sentry (error tracking, backend and browser), Temporal UI (workflow monitoring).

**CI/CD:** GitHub Actions. Quality gate: `make check_all` (`make check` is an alias) — Rails and system tests, worker boot, eager-load check, rubocop, brakeman, eslint, tsc, steiger, Vitest, coverage floors included. CI runs the same checks as two jobs, `make be_check_all` and `make fe_check_all`, per pull request; CI also runs gitleaks (`make secret-scan`).

---

## Key Trade-offs

| Decision | Chosen | Alternative | Rationale |
|----------|--------|-------------|-----------|
| API style | REST | GraphQL | Standard, fits CRUD patterns well |
| Client state | Inertia props + React state | A client-side store | Pages are server-rendered; the server already holds the state |
| Enums | enumerize gem | AR::Enum | Better scopes, i18n, no DB-level integers |
| Container orchestration | Temporal | Sidekiq/Rails jobs | Complex multi-phase lifecycle needs workflow engine |
| Runtime abstraction | Strategy + Runtime | Single Docker implementation | Kubernetes support needed for production scaling |
| Admin panel | Administrate | Custom admin | Fast setup, standard CRUD is sufficient |
| Browser session | Cookie + server-side `UserSession` row | JWT | One session for the web app and its API, revocable from the server; programmatic access uses personal MCP tokens |
