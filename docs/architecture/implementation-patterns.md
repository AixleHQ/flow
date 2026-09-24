# Implementation Patterns & Consistency Rules

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
- **Endpoints:** plural resources — `/api/v1/terminal_sessions`, `/api/v1/projects/:project_id/workflows/:id`
- **Nested:** under the project that owns them — `/api/v1/projects/:project_id/board/tasks/:task_id/comments`
- **Custom actions:** member/collection routes — `POST /api/v1/terminal_sessions/:id/finish`, `PATCH .../board/tasks/:id/move`
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

### Actions render resources explicitly

Each action finds its record inside the request's scope, lets `dynamic_authorize!` check
it, and renders an Alba resource (`app/resources/`) itself, with an explicit status.

```ruby
# app/controllers/api/v1/projects/board/tasks_controller.rb
def show
  task = current_board.board_tasks.find(params[:id])
  render json: BoardTaskResource.new(task).to_h
end

def create
  task = TaskService.create(board: current_board, params: task_params, actor: current_user)
  if task.persisted?
    render json: BoardTaskResource.new(task).to_h, status: :created
  else
    render json: { errors: task.errors.full_messages }, status: :unprocessable_entity
  end
end
```

### Controller Hierarchy

API tree (no `Api::V1::Company::ApplicationController` layer):

```ruby
ApplicationController                    # AuthConcern, allow_browser, underscore_params
  Api::V1::ApplicationController         # JSON API, pagination, rescue_from, dynamic_authorize!
    Api::V1::Company::AssetsController   # inherits directly; uses AuthConcern's session company
    Api::V1::Projects::ApplicationController  # current_project
```

`dynamic_authorize!` is a `before_action` in `Api::V1::ApplicationController` (applies to the whole api/v1 tree). Company controllers inherit directly from it and use AuthConcern's `current_company` — the session company, validated against active memberships on every request. The SPA calls the API on the same cookie session as the page, so never re-resolve the company (for example to the first membership): a multi-company user would write into a company other than the one on screen. `current_project` lives in `Api::V1::Projects::ApplicationController`.

The **Web** namespace has its own base-controller chain:

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

What the controllers return — no envelope around the resource:

- **Single record:** the resource's hash itself — `render json: XResource.new(record).to_h`.
- **Lists:** a bare array of resource hashes. A list that pages says so in headers
  (`X-Total-Count` on the board's task lists), not in a wrapper object. A few endpoints return
  a named key because they carry more than one thing (`{ triggers: [...] }`, `{ sessions: [...] }`).
- **Errors:** `{ error: "message" }` for a refusal or a missing record (the base controller's
  403/404/CSRF handlers); `{ errors: [...] }` for validation messages. An uncaught
  `ActiveRecord::RecordInvalid` is answered with both: `{ error: "a, b", errors: ["a", "b"] }`.
  The frontend's `apiRequest`/`apiMutate` (`shared/lib/apiFetch.ts`) read `message`, then
  `error`, then `errors`, so a new endpoint may use either shape.
- **Keys** are camelCase on the wire: Alba resources camelize their own keys.

### Key Principles
- `Ransack` — filtering: `Model.ransack(params[:q]).result`
- `paginate` — via PaginationConcern (pagy); `inertia_scroll` for Inertia infinite scroll
- No `before_action :set_resource` — find the record inline, inside the request's scope
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
- **Pages:** `app/frontend/pages/` — Inertia page components grouped by product area (server-driven routing); a page's private components and hooks sit next to it
- **Layouts:** `app/frontend/layouts/` — `AuthLayout`, the signed-in shell
- **Shared:** `app/frontend/shared/` — `ui`, `components`, `resources`, `lib`, `theme`, `analytics`, generated `routes.ts`
- **Co-located tests:** `*.test.tsx` next to component
- **API:** `shared/lib/apiFetch.ts` — `fetch` wrapper (CSRF + JSON); most data arrives via Inertia props

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
- Frontend sends: `{ onboardingStateEvent: "go_next" }` (underscored to `onboarding_state_event` on arrival) — setter triggers AASM event
- Active machines:
  - **User:** `state` (active/pending/suspended/archived)
  - **CompanyMembership:** `state` (invited/active/suspended/revoked), `onboarding_state` (step1→step2→completed)
  - **Company:** `state` (active/suspended/archived)
  - **TerminalSession:** `state` (not_started/queued/running/ready/finishing/finished/failed/cancelled)
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
- **Server-side, not client-side.** Alba `transform_keys :lower_camel` in `ApplicationResource` camelizes serialized JSON; `DeepKeyCamelizer`, installed as Inertia's `prop_transformer` in `config/initializers/inertia.rb`, camelizes all Inertia props; `ApplicationController#underscore_params` underscores incoming params
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
- **Controllers:** `rescue_from` in the base controllers — `Api::V1::ApplicationController` (JSON 403, 404, and 422 for invalid records and CSRF failures) and `Web::Company::ApplicationController` (Pundit refusals)
- **Services:** custom exceptions → `Temporalio::Error::ApplicationError`
- **Temporal:** `TemporalExceptions.wrap(error, retryable:, benign:)`
- **Frontend:** `apiFetch` response checks + Mantine notifications for toasts

### Logging
- **Backend:** Lograge (structured JSON) + Sentry (error tracking)
- **Frontend:** Sentry (`shared/lib/sentry.ts`), initialized before the app mounts

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
- **Never** use global loading states → track loading per request (local state around `apiFetch`)
- **Never** validate only on submit → use on blur + on submit
