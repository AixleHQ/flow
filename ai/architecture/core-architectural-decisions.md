# Core Architectural Decisions

**Updated:** 2026-02-21

---

## Data Architecture

**Database:** PostgreSQL 15.3

**ORM:** ActiveRecord — primary for all operations.

**Multi-tenancy:** Company → Project hierarchy with polymorphic `scope` (Company/Project) for scoped resources. All tenant queries filter by `company_id`.

**State machines:** AASM gem. Three active: User (account + onboarding), Company, TerminalSession.

**Enums:** `enumerize` gem. Never `ActiveRecord::Enum`.

**Encryption:** `ActiveSupport::MessageEncryptor` for agent credentials, integration credentials, config item secrets.

**Validation:** Three levels — DB constraints (NOT NULL, FK, unique) → Model validations (Rails) → Service-level business rules.

**Migrations:** Standard Rails migrations. Schema tracked in `db/schema.rb`.

**Caching:** Redis for session state and frequent queries. Rails cache for app-level. CDN for static assets.

---

## Authentication & Authorization

**Authentication:** Google OAuth via OmniAuth. Session-based (no JWT). Internal-only platform, no external API clients.

**Authorization:** Pundit policies. Auto-matched to controllers via `AuthorizationConcern#dynamic_authorize!`. Policy hierarchy mirrors controller namespace hierarchy.

**Roles:** `employee`, `admin`, `super_admin` (via enumerize). Super admin protected — only via seeds/DB.

**Multi-tenancy auth:** Company resolved from `current_user.company`. Project access checked via ownership + collaborator relationship.

---

## Container Execution Architecture

**Core decision:** Strategy + Runtime pattern. Strategies define WHAT to do, Runtimes define WHERE.

**Strategies:**
- `AgentAuthStrategy` — OAuth credential collection via file watching inside container
- `AgentSessionStrategy` — interactive/non-interactive agent sessions with credential injection, log/usage collection
- `ToolExecutionStrategy` — custom tool execution with command, parameters, file mounts, exit code tracking

**Runtimes:**
- `DockerRuntime` — docker-api gem, local Docker daemon
- `KubernetesRuntime` — kubeclient + websocket, Kubernetes Pods + Services + Traefik IngressRoutes

**Phase lifecycle:** `pull_image → create_container → start_container → exec → cleanup` with `before_/after_` hooks.

**Orchestration:** Temporal workflows. `ContainerWorkflow` manages full container lifecycle with signal support for interactive sessions.

**Agent adapters:** Per-agent credential/config handling. Four adapters: ClaudeCode, CursorCli, Codex, GeminiCli. Each defines auth paths, config generation, usage collection method (OTLP or MITM).

---

## API Design

**Pattern:** REST API only. No GraphQL.

**Format:** JSON. `respond_with` for auto format + status.

**Response wrapping:** Lists in `{ items: [...] }`, singles in `{ data: {...} }`.

**Filtering:** Ransack — `Model.ransack(params[:q]).result`.

**Pagination:** Pagy via `PaginationConcern`.

**Documentation:** OAS Rails (auto-generated OpenAPI from controllers).

**Case conversion:** snake_case in API, automatic camelCase ↔ snake_case in frontend via `baseApi.ts`.

**Real-time:** ActionCable for terminal session state updates (`TerminalSessionChannel`).

**Internal endpoints:** `/api/v1/internal/` — WebSocket auth, OTLP usage ingestion. No Pundit.

---

## Frontend Architecture

**Framework:** React 19 + TypeScript 5.9 + Vite 7.3.

**Architecture:** Feature-Sliced Design (app → pages → features → entities → shared).

**State management:** Redux Toolkit (global: API cache, user) + Zustand (local component state). Never mix.

**Routing:** TanStack Router — type-safe, generated routes.

**UI:** Material UI 6.x.

**Forms:** React Hook Form + Zod. Validate on blur + on submit.

**API client:** RTK Query with auto case conversion interceptors. CSRF from meta tag.

---

## Infrastructure

**Development:** Docker Compose — web (Rails + Vite), Temporal, PostgreSQL, Redis.

**Agent containers:** Custom Docker images per agent (claude-code, cursor-cli, codex, gemini-cli) built from shared base image.

**Kubernetes:** Optional runtime for agent containers (Pods + Services + Traefik IngressRoutes). Config in `kube/common/`, `kube/dev/`, and `kube/prod/`.

**File storage:** Shrine + AWS S3 for asset versions, session logs.

**Monitoring:** Lograge (structured JSON logging), Rollbar (error tracking), Temporal UI (workflow monitoring).

**CI/CD:** GitHub Actions. Quality gate: `make check` (tests + rubocop + brakeman + eslint).

---

## Key Trade-offs

| Decision | Chosen | Alternative | Rationale |
|----------|--------|-------------|-----------|
| Auth | Google OAuth only | Multi-provider | Internal tool, simplicity for MVP |
| API style | REST | GraphQL | Standard, fits CRUD patterns well |
| State mgmt | Redux + Zustand | Redux only | RTK for API cache, Zustand for local — cleaner separation |
| Enums | enumerize gem | AR::Enum | Better scopes, i18n, no DB-level integers |
| Container orchestration | Temporal | Sidekiq/Rails jobs | Complex multi-phase lifecycle needs workflow engine |
| Runtime abstraction | Strategy + Runtime | Single Docker implementation | Kubernetes support needed for production scaling |
| Admin panel | Administrate | Custom admin | Fast setup, standard CRUD is sufficient |
| Session auth | Cookie-based | JWT | No external API clients, simpler security model |
