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
  class ToolsController < ApplicationController
    def index
      tools = Tool.merged_for_company(current_company).ransack(params[:q]).result
      respond_with paginate(tools)
    end

    def create
      tool = current_company.tools.create(tool_params)
      respond_with tool
    end

    def update
      tool = current_company.tools.find(params[:id])
      tool.update(tool_params)
      respond_with tool
    end
  end
end
```

### Controller Hierarchy

```ruby
ApplicationController                    # Auth, browser, gon
  Api::V1::ApplicationController         # JSON API, pagination, rescue_from
    Api::V1::Company::ApplicationController  # current_company, dynamic_authorize!
      Api::V1::Company::Projects::ApplicationController  # current_project
```

Each namespace base sets: `before_action :dynamic_authorize!` + scope helper (`current_company`, `current_project`).

### Dynamic Authorization (AuthorizationConcern)

Authorization is automatic via `dynamic_authorize!`:
1. Controller name → Policy class: `Api::V1::Company::ToolsController` → `Api::V1::Company::ToolsPolicy`
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

### Frontend (Feature-Sliced Design)
- **Layers:** app → pages → features → entities → shared
- **Import rule:** upper layers import only from lower layers
- **Co-located tests:** `*.test.tsx` next to component
- **API:** `shared/api/baseApi.ts` — RTK Query with auto case conversion

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
  - **TerminalSession:** `state` (not_started/running/ready/finished/failed)

### Polymorphic Scoping
- Agent, Tool, MCPServer, Skill, Asset, ConfigItem, Repository
- `scope_type` + `scope_id` → Company or Project
- `merged_for_project(project)` → combines internal + company + project (project overrides by name)
- `merged_for_company(company)` → combines internal + company

### Encrypted Fields
- `AgentCredential#config_data` — via `ActiveSupport::MessageEncryptor`
- `Integration#credentials` — encrypted
- `ConfigItem#encrypted_value` — for secrets
- **Rule:** Always use setter (`config_data=`), never write `encrypted_config_data` directly

### Case Conversion (Frontend ↔ Backend)
- **Request:** `decamelizeKeys(data)` — `{ currentUser: {...} }` → `{ current_user: {...} }`
- **Response:** `camelcaseKeys(result.data)` — reverse
- **Location:** `app/frontend/shared/api/baseApi.ts`
- **TS interfaces:** always camelCase

### Error Handling
- **Controllers:** `rescue_from` in `ApplicationController` for global errors
- **Services:** custom exceptions → `Temporalio::Error::ApplicationError`
- **Temporal:** `TemporalExceptions.wrap(error, retryable:, benign:)`
- **Frontend:** RTK Query error handling + MUI Snackbar toasts

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
- **Never** use global loading states → use per-request via RTK Query
- **Never** validate only on submit → use on blur + on submit
