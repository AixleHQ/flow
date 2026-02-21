# Project Structure & Boundaries

**Updated:** 2026-02-21

## Directory Structure

```
app/                                    # Root (Rails monolith)
├── Gemfile                             # Ruby dependencies
├── Dockerfile                          # Web container
├── Makefile                            # Build/test commands
├── docker-compose.yml                  # Dev environment
├── docker-compose.ci.yml              # CI environment
│
├── app/                                # Rails application
│   ├── channels/                       # ActionCable
│   │   └── terminal_session_channel.rb
│   ├── controllers/
│   │   ├── concerns/                   # Auth, Authorization, Pagination
│   │   ├── api/v1/                     # Public API
│   │   │   ├── company/                # Company-scoped
│   │   │   │   ├── projects/           # Project-scoped (nested)
│   │   │   │   └── terminal_sessions/  # Session-nested (artifacts)
│   │   │   └── internal/              # Internal (ws_auth, usage_statistics)
│   │   ├── admin/                      # Administrate panel
│   │   └── web/                        # SPA catch-all
│   ├── dashboards/                     # Administrate dashboards
│   ├── frontend/                       # React SPA (Feature-Sliced Design)
│   │   ├── app/                        # App shell, layouts, providers
│   │   ├── entities/                   # Domain entities (asset, project, user, terminal-session, mcp-server)
│   │   ├── features/                   # Feature modules (15+ features)
│   │   ├── pages/                      # Route pages (20+ pages)
│   │   ├── shared/                     # API, config, lib, model, theme, ui
│   │   └── widgets/                    # AppHeader, AppSidebar, session-*
│   ├── models/                         # ActiveRecord (19 models)
│   ├── policies/                       # Pundit (mirrors controller hierarchy)
│   │   └── api/v1/company/             # Policy per controller
│   │       └── projects/
│   ├── serializers/                    # ActiveModelSerializers (20 serializers)
│   ├── services/
│   │   ├── agents/                     # Agent adapters (4 agents)
│   │   ├── container_strategies/       # Strategies (5: base, agent_base, auth, session, tool)
│   │   ├── container_runtime/          # Runtimes (3: base, docker, k8s)
│   │   ├── github/                     # GitHub API (token, repository)
│   │   ├── container_runtime.rb        # Runtime factory
│   │   ├── container_service.rb        # Phase runner
│   │   ├── agent_credentials_service.rb
│   │   ├── session_context_service.rb
│   │   ├── temporal_service.rb
│   │   ├── usage_statistics_service.rb
│   │   ├── workflow_service.rb
│   │   └── google_omni_auth_service.rb
│   ├── state_machines/                 # AASM state machines
│   ├── temporal/
│   │   ├── activities/
│   │   │   ├── container/phase_activity.rb
│   │   │   ├── session/cleanup_stale_activity.rb
│   │   │   └── asset/cleanup_dismissed_activity.rb
│   │   ├── workflows/
│   │   │   ├── container_workflow.rb
│   │   │   ├── stale_session_cleanup_workflow.rb
│   │   │   └── dismissed_asset_cleanup_workflow.rb
│   │   └── temporal_exceptions.rb
│   ├── uploaders/                      # Shrine uploaders
│   ├── validators/                     # Custom validators
│   ├── mcp/                            # ActionMCP
│   ├── contexts/                       # Application contexts
│   ├── forms/                          # Form objects
│   └── responders/                     # Custom responders
│
├── bin/
│   ├── dev                             # Foreman (Rails + Vite)
│   ├── temporal_worker                 # Temporal Ruby worker
│   ├── docker-entrypoint
│   └── setup
│
├── config/
│   ├── routes.rb                       # API routes
│   ├── settings.yml                    # Application settings (container_runtime, etc.)
│   ├── workflows.yml                   # Workflow definitions
│   ├── mcp.yml                         # MCP configuration
│   ├── storage.yml                     # S3 storage config
│   └── initializers/
│
├── db/
│   ├── migrate/                        # Rails migrations
│   └── schema.rb
│
├── docker/                             # Agent Docker images
│   ├── base/                           # Base image (auth-check, logger, watcher)
│   ├── claude-code/
│   ├── cursor-cli/
│   ├── codex/
│   ├── gemini-cli/
│   ├── otlp-ingest/                    # OTLP telemetry collector
│   ├── remote/                         # Remote DB tools
│   └── shared/                         # Shared utilities (watcher)
│
├── kube/                               # Kubernetes manifests
│
├── test/
│   ├── controllers/                    # Controller tests (mirrors app/controllers/)
│   │   ├── admin/
│   │   ├── api/v1/company/projects/
│   │   └── api/v1/internal/
│   ├── integration/                    # Integration tests
│   │   └── container_workflow_integration_test.rb
│   ├── models/                         # Model tests
│   ├── services/                       # Service tests (mirrors app/services/)
│   │   ├── agents/
│   │   ├── container_runtime/
│   │   ├── container_strategies/
│   │   └── github/
│   ├── temporal/                       # Temporal tests
│   ├── serializers/
│   ├── channels/
│   ├── validators/
│   ├── factories/                      # FactoryBot factories
│   ├── support/                        # Test helpers (auth_helper, stub_support, upload_support)
│   └── test_helper.rb
│
├── ai/                                 # AI planning & architecture docs
│   ├── architecture/
│   ├── epics/
│   └── prd/
│
└── _bmad/                              # BMAD framework
```

## Architectural Boundaries

**API Boundaries:**

**External API Endpoints:**
- `/api/v1/terminal_sessions` — Docker session management
- `/api/v1/projects` — Project CRUD
- `/api/v1/workflows` — Workflow management
- `/api/v1/artifacts` — Artifact management
- `/api/v1/users` — User management

**Internal Service Boundaries:**
- **ContainerManager** (`app/services/container_manager.rb`) — Docker API boundary
- **TemporalService** (`app/services/temporal_service.rb`) — Temporal workflow boundary
- **WorkflowService** (`app/services/workflow_service.rb`) — Workflow business logic boundary

**Authentication & Authorization Boundaries:**
- **Authentication:** Google OAuth via OmniAuth (`config/initializers/omniauth.rb`)
- **Authorization:** Pundit policies (`app/policies/`) for resource-level checks
- **RBAC:** Role checks in models (`User`, `ProjectCollaborator`)

**Data Access Layer Boundaries:**
- **Models:** ActiveRecord models (`app/models/`)
- **Serializers:** API serializers (`app/serializers/`)
- **Services:** Business logic layer (`app/services/`)

**Component Boundaries:**

**Frontend Component Communication:**
- **Pages → Features:** Pages use features for UI
- **Features → Entities:** Features use entities for domain logic
- **Shared → All:** Shared utilities are available everywhere

**State Management Boundaries:**
- **Redux Toolkit:** Global state (`app/frontend/shared/api/`)
- **Zustand:** Local state (inside features/components)

**State Machine Pattern (AASM):**
- **Purpose:** Managing the lifecycle and state transitions for business entities
- **Implementation:** AASM gem for backend state machines
- **Location:** `app/state_machines/`
- **Active State Machines:**
  - `CompanyStateMachine`: Managing company states
    - States: `active` (initial), `suspended`, `archived`
    - Events: `suspend`, `activate`, `archive`
    - Auto-generated scopes: `.active`, `.suspended`, `.archived`
  - `UserStateMachine`: Managing user states
    - Account state machine (column: `state`):
      - States: `active` (initial), `pending`, `suspended`, `archived`
      - Events: `activate`, `suspend`, `archive`, `mark_pending`
    - Onboarding state machine (column: `onboarding_state`):
      - States: `step1` (initial), `step2`, `step3`, `step4`, `completed`
      - Events: `go_next`, `go_previous`, `complete`
      - Guard: `complete` event guarded by `can_complete_onboarding?`
      - Callback: `complete` event triggers `set_onboarding_completed_at`
  - `StateEventConcern`: Provides `available_events`, `available_states` helpers AND auto-generates `{column}_event=` setters for triggering events via attribute assignment
- **Frontend Integration:**
  - API accepts `onboarding_state_event: 'go_next' | 'go_previous' | 'complete'`
  - StateEventConcern converts attribute assignment to AASM event call
  - Invalid events are silently ignored (guard fails = no state change)
- **Note:** Roles and positions use `enumerize`, not state machines
  - Roles: `employee`, `admin`, `super_admin` (enumerize)
  - Positions: `qa`, `pm_po_ba`, `dev`, `designer`, `cto` (enumerize)

**Automatic Case Conversion (Frontend ↔ Backend):**
- **Purpose:** Automatic conversion between camelCase (frontend) and snake_case (backend)
- **Implementation:** `camelcaseKeys` and `decamelizeKeys` in `baseApi.ts`
- **Location:** `app/frontend/shared/api/baseApi.ts`
- **How it works:**
  - **Request (Frontend → Backend):**
    ```typescript
    data: isDecamelize ? decamelizeKeys(data) : data
    // { currentUser: { passwordConfirmation: "..." } }
    // → { current_user: { password_confirmation: "..." } }
    ```
  - **Response (Backend → Frontend):**
    ```typescript
    data: camelcaseKeys(result.data)
    // { current_user: { password_confirmation: "..." } }
    // → { currentUser: { passwordConfirmation: "..." } }
    ```
- **TypeScript Interfaces:** All interfaces are written in camelCase (following TypeScript best practices)
  - Example: `IUpdateCurrentUserRequest`, `IUser`, `ICompany`
- **Benefits:**
  - No need to manually write transform functions
  - TypeScript types in pure camelCase
  - Automatic conversion at the HTTP client level
  - Consistency with the `web_reference` project

**Service Communication Patterns:**
- **Rails → Temporal:** Via TemporalService
- **Rails → Docker:** Via ContainerManager
- **Frontend → Backend:** HTTP REST API via RTK Query

**Data Boundaries:**

**Database Schema Boundaries:**
- **Multi-tenancy:** All tenant tables have `company_id`
- **Core entities:** `users`, `companies`, `projects`, `workflows`
- **Execution tracking:** `workflow_runs`, `step_runs`, `artifacts`
- **Billing:** `usage_events` for cost tracking

**Data Access Patterns:**
- **ActiveRecord:** Main ORM for all DB operations
- **Raw SQL:** For complex analytical queries

**Caching Boundaries:**
- **Redis:** Session state, frequent queries
- **Rails cache:** Application-level caching
- **CDN:** Static assets

**External Data Integration Points:**
- **S3:** Artifact storage (`config/storage.yml`)
- **Temporal:** Workflow orchestration
- **Docker:** Container management
- **GitHub/Linear:** External API integrations (future)

## Requirements to Structure Mapping

**FR Category: Agent Sessions (FR1-FR9)**
- **Controllers:** `app/controllers/api/v1/terminal_sessions_controller.rb`
- **Services:** `app/services/container_manager.rb`
- **Frontend:** `app/frontend/pages/session/`, `app/frontend/features/file-tree/`
- **Temporal:** `app/temporal/workflows/` for session lifecycle
- **Docker:** `docker/claude-code/`, `docker/codex/`, `docker/cursor-cli/`

**FR Category: Workflow Management (FR10-FR18)**
- **Controllers:** `app/controllers/api/v1/workflows_controller.rb` (future)
- **Services:** `app/services/workflow_service.rb`
- **Models:** `app/models/workflow.rb` (future)
- **Frontend:** `app/frontend/pages/workflow/`, `app/frontend/features/workflow-stepper/`
- **Temporal:** `app/temporal/workflows/` for workflow execution

**FR Category: Artifact Management (FR19-FR25)**
- **Controllers:** `app/controllers/api/v1/artifacts_controller.rb` (future)
- **Models:** `app/models/artifact.rb` (future)
- **Uploaders:** `app/uploaders/asset_uploader.rb`
- **Frontend:** `app/frontend/pages/artifacts/`, `app/frontend/features/artifact-viewer/`
- **Storage:** S3 via Shrine (`config/storage.yml`)

**FR Category: Project & Collaboration (FR26-FR31)**
- **Models:** `app/models/project.rb`, `app/models/project_collaborator.rb`
- **Controllers:** `app/controllers/api/v1/projects_controller.rb` (future)
- **Policies:** `app/policies/project_policy.rb` (future)
- **Frontend:** `app/frontend/pages/projects/`, `app/frontend/features/project-card/`

**FR Category: Secrets Management (FR32-FR36)**
- **Models:** `app/models/secret.rb` (future)
- **Services:** `app/services/secrets_service.rb` (future)
- **Encryption:** ActiveSupport::MessageEncryptor
- **Frontend:** `app/frontend/pages/settings/secrets/` (future)

**FR Category: Tools Framework (FR37-FR41)**
- **Models:** `app/models/tool.rb` (future)
- **Services:** `app/services/tool_service.rb` (future)
- **Temporal:** `app/temporal/activities/tool_execution.rb` (future)
- **Docker:** Custom tool containers

**FR Category: Billing & Analytics (FR42-FR46)**
- **Models:** `app/models/usage_event.rb` (future)
- **Services:** `app/services/billing_service.rb` (future)
- **Frontend:** `app/frontend/pages/analytics/` (future)
- **MITM Proxy:** `docker/claude-code/` billing interceptor

**FR Category: User Management (FR47-FR50)**
- **Models:** `app/models/user.rb`, `app/models/company.rb`
- **Controllers:** `app/controllers/api/v1/users_controller.rb` (future)
- **Policies:** `app/policies/user_policy.rb` (future)
- **Frontend:** `app/frontend/pages/users/` (future)
- **Auth:** Google OAuth via OmniAuth

**FR Category: Integrations (FR51-FR53)**
- **Services:** `app/services/integration_service.rb` (future)
- **Temporal:** `app/temporal/activities/github_integration.rb` (future)
- **Frontend:** Integration UI (future)

**Cross-Cutting Concerns:**

**Authentication System:**
- **Config:** `config/initializers/omniauth.rb`
- **Models:** `app/models/user.rb`
- **Frontend:** `app/frontend/shared/api/auth.ts`

**Authorization System:**
- **Policies:** `app/policies/` (Pundit)
- **Models:** Role checks in `User`, `ProjectCollaborator`
- **Frontend:** Permission checks via API

**Multi-tenancy:**
- **Models:** All tenant models have `company_id`
- **Policies:** Company-scoped checks in Pundit
- **Services:** Company filtering in services

**Billing & Cost Tracking:**
- **MITM Proxy:** `docker/claude-code/billing_interceptor.py` (future)
- **Models:** `app/models/usage_event.rb` (future)
- **Services:** `app/services/billing_service.rb` (future)

**Real-time Updates:**
- **Channels:** `app/channels/` (ActionCable)
- **WebSocket:** File tree updates via watcher
- **Frontend:** WebSocket clients in features

## Integration Points

**Internal Communication:**

**Rails → Temporal:**
- **Service:** `TemporalService.start_workflow()`
- **Activities:** `app/temporal/activities/`
- **Workflows:** `app/temporal/workflows/`

**Rails → Docker:**
- **Service:** `ContainerManager.create_session()`
- **API:** Docker API via Unix socket

**Frontend → Backend:**
- **API:** RTK Query (`app/frontend/shared/api/`)
- **Endpoints:** `/api/v1/*` REST API
- **Serializers:** `app/serializers/` for response formatting

**External Integrations:**

**S3 Storage:**
- **Config:** `config/storage.yml`
- **Uploader:** `app/uploaders/asset_uploader.rb`
- **Usage:** Artifact storage

**Temporal Server:**
- **Connection:** gRPC via TemporalService
- **Workflows:** Cross-language workflows (Ruby ↔ Python)

**Docker API:**
- **Connection:** Unix socket
- **Usage:** Container lifecycle management

**Future Integrations:**
- **GitHub:** API for PR creation, code context
- **Linear:** API for task export
- **LLM Providers:** Anthropic, OpenAI, OpenRouter

**Data Flow:**

**Session Creation Flow:**
1. Frontend → Rails API (`POST /api/v1/terminal_sessions`)
2. Rails → ContainerManager (create Docker container)
3. ContainerManager → Docker API
4. Rails → Temporal (start session workflow)
5. Temporal → Python Worker (if needed)
6. Response → Frontend (session URLs)

**Workflow Execution Flow:**
1. Frontend → Rails API (start workflow)
2. Rails → TemporalService (start workflow)
3. Temporal → Ruby/Python Activities
4. Activities → Services (business logic)
5. Services → Models (data persistence)
6. Temporal → Frontend (status updates via WebSocket)

```
Controller → Service → Model
         → Temporal (async)
         → Runtime (containers)

PhaseActivity → ContainerService → Strategy → Runtime
                                 → SessionContextService
                                 → AgentCredentialsService
                                 → Adapter
```

### Data Access

- **Models:** ActiveRecord ORM for all DB operations
- **Multi-tenancy:** Company → Project polymorphic scoping
- **Serializers:** ActiveModelSerializers for API responses
- **Encryption:** ActiveSupport::MessageEncryptor for credentials, secrets

### Frontend Boundaries (Feature-Sliced Design)
```
app (shell, layouts, providers)
  ↑
pages (route-level, compose features + widgets)
  ↑
features (business logic UI modules)
  ↑
entities (domain objects: user, project, asset, session)
  ↑
shared (api, lib, ui, theme, config, model)
```


**Testing Patterns:**
- **Factories & Sequences:** Always use FactoryBot with sequences for data generation
- **Factory Rules:** In factories, nothing should be written directly in fields, except `password_confirmation` which duplicates `password`
- **Data Generation:** All values are generated via sequences (email, name, password, etc.)
- **Traits:** Use traits for variations (for example, `:super_admin`, `:with_company`)

**Code Quality Checks (MANDATORY):**
- **Command:** `make check` (runs inside the Docker container)
- **What it runs:**
  1. `rails test` - all unit tests
  2. `rubocop -a` - Ruby linting with autofix
  3. `brakeman` - security scanning
  4. `yarn lint:fix` - ESLint + Prettier with autofix
- **When to run:** REQUIRED before completing any story/task
- **Rule:** All checks must pass without errors before committing
- **Note:** Some pre-existing warnings may be in files not touched by the current task

**Admin Panel:**
- **Approach:** Use the Administrate gem for the admin panel
- **No custom dashboard:** Standard resource controllers without a custom dashboard controller
- **Rationale:** Administrate provides all the needed features out of the box

| Integration | Mechanism | Location |
|-------------|-----------|----------|
| Docker | docker-api gem (Unix socket) | `container_runtime/docker_runtime.rb` |
| Kubernetes | kubeclient + websocket | `container_runtime/kubernetes_runtime.rb` |
| Temporal | gRPC (temporalio gem) | `temporal_service.rb` |
| S3 | aws-sdk-s3 via Shrine | `uploaders/`, `config/storage.yml` |
| GitHub | Octokit + GitHub App JWT | `services/github/` |
| Google OAuth | OmniAuth | `config/initializers/omniauth.rb` |
| ActionCable | WebSocket | `channels/terminal_session_channel.rb` |
| MCP | ActionMCP engine | `app/mcp/`, `config/mcp.yml` |
| OTLP | HTTP endpoint | `internal/usage_statistics_controller.rb` |

**Field Naming Decisions:**
- **`state` vs `status`:** Use `state` for the User model (team preference)
- **Enumerize scopes:** `enumerize :state, scope: true` creates `User.active`, not `User.with_state(:active)`
- **Rationale:** Shorter and more readable syntax

**Authorization Patterns:**
- **AdminConstraint:** Not used, protection only via `authenticate_admin!` in the controller
- **Rationale:** A check in the controller is sufficient, a constraint is redundant for the current requirements

**Project Collaborators:**
- **`add_collaborator` method:** Provided by the AASM gem or a custom implementation
- **Rationale:** AASM is used for state machine functionality

**Asset Organization:**
- **Rails assets:** `app/assets/` (SCSS, images)
- **Frontend assets:** `app/frontend/shared/ui/` for components
- **Static files:** `public/` directory
- **S3:** Artifacts via Shrine uploader

```
Frontend → POST /api/v1/terminal_sessions
  → TerminalSessionsController#create
    → TerminalSession.create! (state: not_started)
    → TemporalService.start_workflow(ContainerWorkflow)
      → PhaseActivity.run(pull_image)    → Strategy → Runtime
      → PhaseActivity.run(create_container) → Strategy → Runtime
      → PhaseActivity.run(start_container)  → Strategy → Runtime (wait_for_ready)
      → Signal: mark_ready → TerminalSession.mark_ready!
      → ActionCable broadcast → Frontend
      → Await finish signal
      → PhaseActivity.run(exec)          → Strategy (collect logs, usage)
      → PhaseActivity.run(cleanup)       → Strategy → Runtime (stop, remove)
```

**Development Server Structure:**
- **Command:** `bin/dev` (Foreman)
- **Processes:** Rails server + Vite dev server
- **Hot reloading:** Vite HMR for frontend
- **Docker:** `docker-compose up` for infrastructure

### Data Flow: Tool Execution

```
Frontend → POST /api/v1/terminal_sessions (with tool_id)
  → TerminalSession.create! → TemporalService.start_workflow
    → PhaseActivity(pull_image)      → ToolExecutionStrategy → Runtime
    → PhaseActivity(create_container) → env vars, tool_files mount
    → PhaseActivity(start_container)  → no wait_for_ready (no ports)
    → PhaseActivity(exec)             → wait_container + collect stdout/stderr
    → PhaseActivity(cleanup)          → stop + remove
```

## Testing Patterns

- **Factories:** FactoryBot with sequences — never hardcode values in factories
- **Backend runner:** `docker exec app-web-1 bundle exec rails test`
- **Integration tests:** `test/integration/` — combinatorial strategy × runtime × agent tests
- **Stubs:** `test/support/stub_support.rb` — reusable Docker/K8s runtime mocks
- **Coverage:** controllers, models, services, strategies, runtimes, adapters, temporal, serializers, channels, validators

## Quality Checks

```bash
make check     # Inside Docker: rails test + rubocop -a + brakeman + yarn lint:fix
make test      # Rails tests only
make lint      # Rubocop + ESLint
```
