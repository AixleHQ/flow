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
- **API clients:** the library for that API (`octokit`, `gitlab`), used from the provider's service in `app/services/<provider>/`; our own client under `app/services/<provider>/` only when no library we use covers the API
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
- These scopes decide what a **picker** offers. Whether an id may be **referenced** is decided by `TenantScope` — a different question (see Tenant References)

### Tenant References
- **Storing an id:** a record that stores the id of another row validates it with `TenantIdsValidator` (`app/validators/tenant_ids_validator.rb`) — one rule for a single foreign key, an id array and an association collection:
  ```ruby
  validates :x, tenant_ids: { model: X }, if: -> { new_record? || will_save_change_to_x? }
  ```
  - `project:` / `company:` → the record's methods that return its tenant (default: `project`, and that project's company)
  - `lenient: true` → an id of a deleted row passes, for references that outlive their row
  - `error_on:` → the attribute that gets the error
  - Validate only when the value can change. For a column (a foreign key or an id array), use the `if:` above. For an association collection (`has_and_belongs_to_many`), which has no `will_save_change_to_<name>?` method, validate where the ids arrive instead, e.g. `on: :create` (`TerminalSession`)
- **Examples:** `Repository#integration_id` (`project: :scope_project, error_on: :integration`), `WorkflowRun#input_asset_ids` / `#repository_ids` (with the change guard), `TriggerBinding#subject_column_id` (`error_on: :subject_column`), the `TerminalSession` associations (`company: :company, on: :create`)
- **Reading an id back:** an id read from a JSON column, a stored id list or a tool argument is resolved through the tenant, `TenantScope.owned(X, project:).find_by(id: id)` / `.where(id: ids)`, never `X.find(id)` / `X.find_by(id:)`, so a foreign id is not found. Examples: `SessionContextService` (`:445`), `TriggerEngine` (`:342`), `WorkflowStepStrategy` (`:161`), `Chat::SlackProvider` / `Chat::TeamsProvider`, `InternalTools::GetConfigItem`, `AzureDevopsContext`, `TerminalSession` (`:310`). The `Tenant/ScopedToolLookup` cop enforces it in `app/services/internal_tools` and `app/services/personal_tools` only
- **Ownership** is defined in one place: `TenantScope.owned` (`app/services/tenant_scope.rb`). Ownership only, no enabled/attachable filtering; platform-owned rows (code tools, internal MCP servers) belong to every tenant. A new model that can be referenced gets its rule there (otherwise `owned` raises `no tenant rule for …`), not in a model scope of its own
- **Database keys:** polymorphically scoped tables carry real `project_id` / `company_id` columns, kept in step with the scope pair by `TenantColumns`, with foreign keys, a composite key `(project_id, company_id)` → `projects (id, company_id)` and a check against the scope pair (`AddTenantColumnsToScopedResources`, which also ties `repositories (integration_id, company_id)` to `integrations (id, company_id)`). A table that carries `company_id` directly gets the same composite keys (`CreateRunners`). The company boundary holds in the database itself; a new scoped table follows the same pattern

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
- **A service takes named parameters, never the request, its body or its headers,** so another service, a CLI command or a controller can call it. E.g. `Runners::Registration.register!(credential, name:, os:, arch:, facts:, auto_update:, runner_version:, protocol_version:)` and `Runners::Operations.record_result!(operation, status:, exit_code:, stdout:, stderr:, data:, error:)`.
- **The controller turns the request into parameters.** It checks the headers (their presence, their form, and a rule on a header's value such as the runner gateway's version over 255 characters or below `min_version`), authentication, and the body's shape against its schema (`Runners::ProtocolSchema.valid?`), and refuses itself when one fails. It then maps the body to the service's parameters, defaults included.
- **The service makes the domain checks and raises a named error.** Examples: `WorkflowAggregateSave::Invalid`, `Chat::ConnectCodes::Refused`, `Templates::Package` (checks `template.yaml` against its schema itself), and the runner gateway's `Runners::Credentials::Refused` (e.g. `runner_revoked`, or `invalid_registration` for a machine whose validations fail).
- **The controller maps a service's named error to a status,** through `rescue_from` (the runner gateway's `Runners::Credentials::Refused` → `REFUSAL_STATUS`, whose codes the controllers' own refusals use too) or a `rescue` in the action (`aggregates_controller.rb`, `chat_connect_codes_controller.rb`).
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
- **Never** hand-write a tenant check for a stored id (`validate :x_within_project`) → use `validates :x, tenant_ids: { model: X }`
- **Never** repeat a `TenantScope` ownership rule in a model scope → add the model to `TenantScope.owned`; `visible_for_*` is for pickers, not for validating references
- **Never** resolve a stored or user-supplied id across every company (`X.find(id)`, `X.find_by(id:)`) → use `TenantScope.owned(X, project:).find_by(id:)`
- **Never** do IO, call a service or reach a higher layer from a model validation → a validation may read the model's own associations, query for uniqueness and call pure data and rule code (e.g. `Runners::ConfigSchema`); a check that needs an external call belongs in a service or a health check (DESIGN.md §5.1 of agent-runtimes)
- **Never** skip `# frozen_string_literal: true`
- **Never** create `before_action :set_resource` → find inline
- **Never** stub Mocha `.returns` with a block for dynamic fake objects → use `Object.new` + `define_singleton_method`
- **Never** use global loading states → track loading per request (local state around `apiFetch`)
- **Never** validate only on submit → use on blur + on submit
- **Never** put business logic in a controller (queries beyond finding the record in the request's scope, building domain rows, find-or-create with race handling, defaults) → a service with named parameters; the controller turns the request into parameters, calls it and renders (see Structure Patterns → Services and Error Handling)
- **Never** accept lenient input at an interface (`ActiveModel::Type::Boolean.new.cast`, `"true"`/`1` taken as a boolean, a value of the wrong type ignored) → strict types: a wrong type is refused, and the schema or the permitted params are the only definition
- **Never** keep state in an object that doesn't own it → ask whose the state is and how long it lives. An object keeps only what is its own for its whole life: configuration, clients, values memoized for that life (`@project ||=` in a controller, which lives for one request). What belongs to one call, one record or one run (a request, a session, a task) goes in as an argument and comes back as a result, or is stored on that record. Instance variables that accumulate across calls, `Thread.current`, globals and class-level mutable state are the usual signs of state in the wrong place
- **Never** give a reader side effects → a method that returns state doesn't reset or change it
- **Never** check a capability with `respond_to?` on an object behind an abstraction (`ContainerRuntime::BaseRuntime`, the strategies, the agent adapters) → declare the method on the base with a default, as `list_session_resources` is `[]` on a runner
- **Never** pass data back through an argument (a collector array or hash the caller passed in, an object the caller reads afterwards) → return it, and let the caller combine the results. A method changes an argument only when changing it is what the method is for, and its name says so
- **Never** make one decision at several call sites → one factory or polymorphism (`ContainerRuntime.for_session`)
- **Never** write a query with a domain meaning at its call site → name it as a scope on the model it returns (a class method for a single record), and compose named scopes where it's used. A query has a domain meaning when it can be named (a person's live GitHub connection, a session's secret accesses, the projects of a company a person can reach), when it is needed in more than one place, or when it reaches into a column's structure (JSON paths, raw SQL). A lookup by id or by one plain attribute inside the request's scope stays inline. Ownership is still `TenantScope.owned`, never a model scope
- **Never** compute a model's derived value outside the model and hand it to a serializer (`params: { states: … }`, a precomputed map) → a model method, serialized as an attribute; add `includes` (a scoped association where the full one would load too much) to avoid extra queries
- **Never** make an HTTP request in a domain service (`Net::HTTP`, Faraday, HTTParty, a request built on `SafeHttp.http_for`, an API path written out, a status code read) → a client for that API makes the request; the service calls the client's named methods and maps the client's errors to its own named errors
- **Never** hand-write a client for an API that a library we already use covers → before writing HTTP code, look in the `Gemfile` for a library for that API (`octokit`, `gitlab`) and use it. If the library lacks a call, use its generic request method for that call. Write our own client only when the library can't do the job, and say why in the PR. OAuth token exchange, refresh and revocation go through the OAuth engine, not through a provider's service; the OAuth engine (`Oauth::TokenService`) is the client for these calls. Examples: `Github::UserTokenService` on Octokit, `Gitlab::TokenService` on the `gitlab` gem, `Oauth::TokenService` for the OAuth calls
- Existing code that breaks these rules is not a precedent: new code doesn't copy it
