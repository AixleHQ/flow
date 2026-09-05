# Implementation Patterns & Consistency Rules

**Updated:** 2026-02-21

---

## Naming Conventions

### Database
- **Tables:** snake_case, plural — `users`, `terminal_sessions`, `config_items`
- **Columns:** snake_case — `user_id`, `created_at`, `scope_type`
- **Foreign keys:** `{table}_id` — `user_id`, `project_id`
- **Polymorphic:** `scope_type` + `scope_id` (not `{model}_type`)
- **JSONB columns:** snake_case — `metadata`, `session_config`, `settings`
- **Array columns:** plural — `models`, `tags`, `selected_agents`

### API
- **Endpoints:** plural resources — `/api/v1/company/tools`, `/api/v1/company/projects/:id/agents`
- **Nested:** max 2 levels — `/api/v1/company/projects/:project_id/terminal_sessions`
- **Custom actions:** member/collection routes — `POST /terminal_sessions/:id/finish`
- **Query params:** snake_case — `params[:q]` for Ransack search

### Code

| Context | Convention | Example |
|---------|-----------|---------|
| Ruby classes | PascalCase | `ContainerService`, `AgentAuthStrategy` |
| Ruby methods/vars | snake_case | `pull_image`, `container_id` |
| Ruby constants | UPPER_SNAKE_CASE | `HEALTH_CHECK_TIMEOUT` |
| TS components | PascalCase files | `UserCard.tsx`, `SessionLauncher.tsx` |
| TS functions/vars | camelCase | `getUserData()`, `sessionId` |
| TS constants | UPPER_SNAKE_CASE | `API_BASE_URL` |

### Field Naming
- **State columns:** `state` (not `status`) — AASM convention
- **Enums:** via `enumerize` gem, never `ActiveRecord::Enum`
- **Encrypted:** `encrypted_config_data` (column), `config_data` (accessor)

---

## API Controller Patterns

### Minimalist Style
Controllers: 2-3 lines per action max. Use `respond_with` for automatic format + status.

```ruby
module Api::V1::Company
  class AssetsController < Api::V1::ApplicationController
    def index
      assets = current_company.assets.ransack(params[:q]).result
      respond_with paginate(assets)
    end

    def create
      asset = current_company.assets.create(asset_params)
      respond_with asset
    end

    def update
      asset = current_company.assets.find(params[:id])
      asset.update(asset_params)
      respond_with asset
    end
  end
end
```

### Controller Hierarchy

API tree (no `Api::V1::Company::ApplicationController` layer):

```ruby
ApplicationController                    # Auth, browser, gon
  Api::V1::ApplicationController         # JSON API, pagination, rescue_from, dynamic_authorize!
    Api::V1::Company::AssetsController   # inherits directly; defines current_company inline
    Api::V1::Projects::ApplicationController  # current_project
```

`dynamic_authorize!` is a `before_action` in `Api::V1::ApplicationController` (applies to the whole api/v1 tree). Company controllers inherit directly from it and define `current_company` inline; `current_project` lives in `Api::V1::Projects::ApplicationController`.

The genuine 4-level base-controller chain exists only in the **Web** namespace:

```ruby
Web::ApplicationController
  Web::Company::ApplicationController           # current_company
    Web::Company::Projects::ApplicationController  # current_project
```

### Dynamic Authorization (AuthorizationConcern)

Authorization is automatic via `dynamic_authorize!`:
1. Controller name → Policy class: `Api::V1::Company::AssetsController` → `Api::V1::Company::AssetsPolicy`
2. Action name → policy method: `index` → `index?`, `create` → `create?`
3. `policy_record` is overridable per controller

### Response Formats
- **Lists:** `{ items: [...] }` — via `ApplicationSerializer` base
- **Single:** `{ data: {...} }` — via `ApplicationSerializer` base
- **Errors:** `{ errors: { field: ["msg"] } }` (validation) or `{ error: "msg" }` (other)
- **Pagination:** `PaginationConcern` with pagy — adds `X-Total`, `X-Per-Page` headers

### Key Principles
- `respond_with` — auto format + status
- `Ransack` — filtering: `Model.ransack(params[:q]).result`
- `paginate` — via PaginationConcern
- No `before_action :set_resource` — find record inline for explicitness
- `@variable ||=` — memoization within request

---

## Structure Patterns

### Backend (Rails)
- **Services:** `app/services/` — all business logic
- **Strategies:** `app/services/container_strategies/` — Strategy pattern for container types
- **Runtimes:** `app/services/container_runtime/` — Runtime abstraction for Docker/K8s
- **Adapters:** `app/services/agents/` — per-agent credential/config logic
- **Concerns:** `app/controllers/concerns/`, `app/models/concerns/`
- **State machines:** `app/state_machines/` — AASM definitions
- **Temporal:** `app/temporal/workflows/`, `app/temporal/activities/`

### Frontend (Inertia + React)
- **Pages:** `app/frontend/pages/` — one component per Inertia page (server-driven routing)
- **Shared:** `app/frontend/shared/` — `components`, `lib`, `resources`, `ui`, `ui-inertia`, `theme`, `config`, generated `routes.ts`
- **Co-located tests:** `*.test.tsx` next to component
- **API:** `shared/lib/apiFetch.ts` — `fetch` wrapper (CSRF + JSON); most data arrives via Inertia props (no RTK Query)

### Test Organization
- **Mirrors app structure:** `test/controllers/`, `test/services/`, `test/models/`
- **Factories:** `test/factories/` — FactoryBot with sequences, traits
- **Support:** `test/support/` — shared helpers (auth, stubs, uploads)
- **Integration:** `test/integration/` — cross-cutting tests

---

## Process Patterns

### State Machines (AASM)
- Located in `app/state_machines/`
- `StateEventConcern` auto-generates `{column}_event=` setters for API use
- Frontend sends: `{ onboarding_state_event: "go_next" }` — setter triggers AASM event
- Active machines:
  - **User:** `state` (active/pending/suspended/archived), `onboarding_state` (step1→completed)
  - **Company:** `state` (active/suspended/archived)
  - **TerminalSession:** `state` (not_started/running/ready/finishing/finished/failed)
  - **WorkflowRun:** `state` (pending/running/paused/completed/failed/cancelled)

### Polymorphic Scoping
- Agent, Tool, Workflow, MCPServer, Skill, Asset, ConfigItem, Repository
- `scope_type` + `scope_id` → Company or Project
- `visible_for_project(project)` → union of Company-scoped + Project-scoped rows (System-scoped excluded; no name override)
- `visible_for_company(company)` → Company-scoped rows
- `for_project(project)` / `for_company(company)` → a single scope only

### Encrypted Fields
- `AgentCredential#config_data` — via `ActiveSupport::MessageEncryptor`
- `Integration#credentials` — encrypted
- `ConfigItem#encrypted_value` — for secrets
- **Rule:** Always use setter (`config_data=`), never write `encrypted_config_data` directly

### Case Conversion (Frontend ↔ Backend)
- **Server-side, not client-side.** Alba `transform_keys :lower_camel` in `ApplicationResource` camelizes serialized JSON; `InertiaPropsCamelizer` (`config/initializers/inertia.rb`) camelizes all Inertia props
- **TS types:** Typelizer generates camelCase interfaces (`config/initializers/typelizer.rb`)
- **Rule:** Ruby stays snake_case; TS interfaces are always camelCase

### Configuration & Environment Variables

- **One aggregation point.** Every environment variable is declared in `config/settings.yml`
  (ERB: `<%= ENV['X'] || default %>`), grouped by domain, with per-environment overrides in
  `config/settings/<env>.yml`. App code reads `Settings.temporal.task_queue`, never
  `ENV["TEMPORAL_TASK_QUEUE"]`.
- **Why:** one inventory of what a deploy needs, defaults visible next to the key, no `ENV` typo
  silently becoming `nil` inside a service, and tests stub one config object instead of mutating
  process state.
- **Exceptions** (things loading before Settings or outside the app process): `config/boot.rb`,
  `config/application.rb`, `config/puma.rb`, `config/environments/*.rb`, `config/database.yml`,
  the production fail-fast checks in `config/initializers/required_env.rb`, boot-time
  kill-switch flags (e.g. `AIXLE_TOOLS_RECONCILE_ON_BOOT`), and Dockerfile / docker-compose /
  CI config. Each raw `ENV` read outside those carries a comment saying why.
- **Adding a var** means: `config/settings.yml` + `.env.example` + deploy config, in the same
  change. A var referenced only from code is invisible to whoever deploys it.
- Reviewer's grep: `grep -rnE "ENV\[|ENV\.fetch" app` stays empty — today its only hit is a false
  positive on the `BEDROCK_MODEL_ENV` constant. `RAILS_MAX_THREADS` now arrives as
  `Settings.temporal.worker_max_threads` (Temporal activity slots + the worker's DB pool in
  `bin/temporal_worker`, which runs after `config/environment`).

### Error Handling
- **Controllers:** `rescue_from` in `ApplicationController` for global errors
- **Services:** custom exceptions → `Temporalio::Error::ApplicationError`
- **Temporal:** `TemporalExceptions.wrap(error, retryable:, benign:)`
- **Frontend:** `apiFetch` response checks + Mantine notifications for toasts

### Logging
- **Backend:** Lograge (structured JSON) + Rollbar (error tracking)
- **Frontend:** structured console logging

---

## Anti-Patterns

- **Never** use `ActiveRecord::Enum` → use `enumerize`
- **Never** use fixtures → use FactoryBot factories
- **Never** hardcode values in factories → use sequences
- **Never** write `encrypted_config_data` directly → use `config_data=` setter
- **Never** mix camelCase/snake_case in same context
- **Never** forget `company_id` filter in multi-tenant queries
- **Never** skip `# frozen_string_literal: true`
- **Never** create `before_action :set_resource` → find inline
- **Never** stub Mocha `.returns` with a block for dynamic fake objects → use `Object.new` + `define_singleton_method`
- **Never** return bare arrays from API → always wrap in `items`/`data`
- **Never** use global loading states → track loading per request (local state around `apiFetch`)
- **Never** validate only on submit → use on blur + on submit
