---
project_name: 'aixle'
date: '2026-09-24'
status: 'complete'
optimized_for_llm: true
---

# Project Context for AI Agents

_Critical rules and patterns for implementing code in this project._

---

## Technology Stack

Versions are not listed here — read them from `.ruby-version`, `Gemfile.lock`,
`package.json` / `yarn.lock`, and `docker-compose.yml`.

**Core:**
- **Backend:** Ruby on Rails, Ruby (`.ruby-version`)
- **Frontend:** React 19, TypeScript
- **Bridge:** Inertia.js (`inertia_rails` + `@inertiajs/react`)
- **UI:** Mantine 9 (core, dates, form, hooks, modals, notifications) + Tabler Icons
- **Database:** PostgreSQL (citext, plpgsql)
- **Cache / Action Cable / Rack::Attack:** Redis
- **Background jobs:** Solid Queue (PostgreSQL)
- **Orchestration:** Temporal (temporalio gem)
- **Build:** Vite + vite-plugin-ruby

**Key Dependencies:**
- **Serialization:** Alba + Typelizer (auto-generated TS types)
- **Forms:** @mantine/form + Zod via `zod4Resolver` (mantine-form-zod-resolver); Inertia useForm for simple cases
- **Real-time:** `inertia_cable` gem over Action Cable; the frontend subscribes with its own `useInertiaCableStream` hook on `@rails/actioncable`
- **DnD:** @dnd-kit/core + @dnd-kit/sortable
- **Auth:** email + password (has_secure_password, no Devise) + OmniAuth (Google) + invitations; Pundit
- **Storage:** Shrine + AWS S3 + Uppy (frontend uploads)
- **Container (Docker):** docker-api
- **Container (K8s):** kubeclient + websocket-client-simple
- **MCP:** mcp gem (official Ruby SDK)
- **Enums:** enumerize gem (NOT ActiveRecord enums)
- **State machines:** aasm gem
- **Pagination:** Pagy
- **Search/Filter:** Ransack
- **Monitoring:** Sentry (sentry-ruby, sentry-rails, @sentry/react)
- **Code editor:** CodeMirror (@uiw/react-codemirror)
- **Terminal:** xterm.js (@xterm/xterm)
- **Charts:** Recharts
- **Route helpers:** ts_routes gem → auto-generated `app/frontend/shared/routes.ts`

---

## Architecture Patterns

### Inertia Monolith (Server-Driven)

Rails controllers render React pages via Inertia. No client-side router — all navigation is server-routed.

```
Browser → Inertia Request → Rails Controller → render inertia: "Page", props: { ... } → React Page
```

### camelCase Conversion Pipeline

Frontend sends camelCase → Rails receives snake_case → Alba responds in camelCase.

| Layer | Mechanism | Direction |
|---|---|---|
| **Incoming params** | `ApplicationController#underscore_params` (`deep_transform_keys!(&:underscore)`) | camelCase → snake_case |
| **Inertia props** | `InertiaRails.config.prop_transformer` → `DeepKeyCamelizer` (`config/initializers/inertia.rb`) | snake_case → camelCase |
| **Alba resources** | `ApplicationResource` has `transform_keys :lower_camel` | snake_case → camelCase |
| **Typelizer types** | `properties_transformer` (`camelize(:lower)`) | snake_case → camelCase |

**CRITICAL:** `wrap_parameters false` is set on `Web::ApplicationController` and `Api::V1::ApplicationController`. Without it, Rails `ParamsWrapper` auto-adds an empty wrapper key that collides with the underscored camelCase key.

### Controller Hierarchy

```
ApplicationController (AuthConcern, allow_browser, underscore_params)
├── Web::ApplicationController (wrap_parameters false, inertia_share: flash, settings, current_user, projects)
│   ├── Web::Company::ApplicationController (Pundit, AuthorizationConcern, layout "inertia", require_auth,
│   │   │                                    require_active_membership!, dynamic_authorize!, deny_read_only_mutation!,
│   │   │                                    inertia_share: permissions)
│   │   └── Web::Company::Projects::ApplicationController (current_project, inertia_share: project, projectPermissions)
│   │       └── Feature controllers (boards, workflows, sessions, etc.)
│   ├── Web::SessionsController (login/logout, Google OAuth callback)
│   ├── Web::InvitationsController (accept, decline, sign up)
│   ├── Web::ProfileController
│   └── Web::OnboardingController
└── Api::V1::ApplicationController (JSON, Pundit, PaginationConcern, CSRF-protected, authenticate_user!, dynamic_authorize!)
    ├── Api::V1::Internal::ApplicationController (no user session, no Pundit: ws_auth, usage_statistics)
    └── Api::V1::AssetsController (presign, upload)

Administrate::ApplicationController
└── Admin::ApplicationController (authenticate_admin!)

ActionController::API (no browser session; each authenticates its own caller)
├── MCPController (/mcp — a session key or a personal MCP token)
├── Webhooks:: (GitHub, GitLab, Azure DevOps, Slack, generic ingress — signature/secret verification)
└── Container callbacks: CloudCredentials, GitCredentials, AzureGitCredentials, AgentCredentialSync (per-session derived keys)
```

### Serialization: Alba Resources

Records reach Inertia props and JSON responses through Alba resources (`ApplicationResource` subclasses in `app/resources/`); Typelizer turns them into the TypeScript types.

```ruby
# ✅ Inertia page
render inertia: "Sessions/ShowPage", props: {
  session: -> { TerminalSessionResource.new(session).to_h }
}

# ✅ JSON API (same resource)
render json: TerminalSessionResource.new(session).to_h

# ❌ NEVER for a record — bypasses type generation
render inertia: "Page", props: { session: { id: session.id } }
```

### Shared Props (Auto-Injected)

`Web::ApplicationController` injects `flash` and `settings`, plus `current_user` and `projects` when signed in, via `inertia_share`.
`Web::Company::ApplicationController` adds `permissions`; `Web::Company::Projects::ApplicationController` adds `project` and `projectPermissions`.

Frontend reads these via `usePage().props` or typed `SharedProps`.

### Container Execution Framework

```
Temporal Workflow → PhaseActivity → ContainerService → Strategy → Runtime
```

**Key classes:**
- `ContainerService` — phase runner, calls `before_X`, `X`, `after_X` hooks
- `ContainerRuntime.build` — factory, returns Docker or Kubernetes runtime based on Settings
- `BaseStrategy` → `AgentBaseStrategy` → `AgentAuthStrategy` / `AgentSessionStrategy`
- `BaseStrategy` → `ToolStrategy` → `CustomToolStrategy` / `InternalToolStrategy`
- `BaseRuntime` → `DockerRuntime` / `KubernetesRuntime`
- `BaseAdapter` → `ClaudeCodeAdapter` / `CursorCliAdapter` / `CodexAdapter` / `GeminiCliAdapter` / `AntigravityCliAdapter` / `GrokAdapter` / `KiroCliAdapter`

**Phases:** `pull_image → create_container → start_container → exec → cleanup`

### Multi-tenancy & Scoping

Polymorphic `scope` (Company or Project) used by: Agent, Tool, Workflow, MCPServer, Skill, Asset, ConfigItem, Repository.

Pattern: `visible_for_project(project)` → unions code/platform + company-scoped + project-scoped rows. No name-level override; System-scoped and non-attachable meta/Builder rows are excluded via `user_attachable`. (`visible_for_company` is the company-level analogue.)

### Encrypted Fields

- `AgentCredential#config_data` — uses `encryptor.encrypt_and_sign` / `decrypt_and_verify`
- `Integration#credentials` — encrypted
- `ConfigItem#encrypted_value` — for secrets

**Important:** Always use setter (`config_data=`) to write, never write `encrypted_config_data` directly.

### TerminalSession State Machine

```
enqueue          not_started → queued                      (admission queue)
start            not_started | queued → running
mark_ready       not_started | running → ready
start_finishing  not_started | running | ready → finishing
finish           finishing → finished
fail             not_started | queued | running | ready | finishing → failed
cancel           not_started | queued | running | ready | finishing → cancelled
```

Source of truth: `app/state_machines/terminal_session_state_machine.rb`.

State changes go through these events, with one exception: `Activities::Container::AdmittedPhaseActivity#finalize_session`
settles the final state from what the runtime reported, which can mean a transition the machine does not
offer (a finished session relabelled failed when its output collection failed). Transition callbacks only
assign attributes (they persist with the state); anything that leaves the process, such as waking the
parent workflow run, waits for the commit (`ActiveRecord.after_all_transactions_commit`).

---

## Implementation Rules

### Ruby/Rails

- `# frozen_string_literal: true` — always
- Use `enumerize` gem for enums, never `ActiveRecord::Enum`
- Use `aasm` for state machines
- Factories via `factory_bot_rails`, not fixtures
- Mocks via `mocha`
- WebMock for HTTP stubs in tests
- Multi-tenancy: always filter by `company_id`
- Config: read `Settings.*`, never `ENV[...]` in app code — every env var is aggregated in
  `config/settings.yml` (+ `config/settings/<env>.yml`). Exceptions are only things that load
  before Settings or outside the app process: `config/boot.rb`, `config/application.rb`,
  `config/puma.rb`, `config/environments/*.rb`, `config/database.yml`, the fail-fast presence
  checks in `config/initializers/required_env.rb`, boot kill-switch flags, and
  Dockerfile/compose/CI. A new env var lands in `settings.yml` + `.env.example` + deploy config
  in the same change.
- Authorization: Pundit policies for all resources, `BaseContext` / `ProjectContext` as policy context
- Serialization: Alba resources for all Inertia props and new JSON endpoints

### Inertia Rendering

```ruby
render inertia: "Projects/Board/BoardPage", props: {
  board: -> { BoardResource.new(board).to_h },
  heavy: InertiaRails.defer { expensive_query },
  cable_stream: -> { inertia_cable_stream(board) },
}
```

**CRITICAL: Lambda Wrapper Rule** — when a page has ANY `InertiaRails.defer` prop, ALL eager Hash/Array props MUST be wrapped in `-> { ... }`. Plain Hash values get corrupted during partial reloads (scalars filtered out, arrays leak through).

| Prop type | How to declare | Why |
|---|---|---|
| Eager data (Hash/Array) | `-> { Resource.new(r).to_h }` | Atomic filtering on partial reload |
| Deferred data | `InertiaRails.defer { ... }` | Already a Proc internally |
| Simple scalar (string/nil) | Plain value OK | Not recursively traversed |
| Always-included | `InertiaRails.always { ... }` | Already a Proc internally |

### Real-Time: Inertia Cable Only

All real-time updates go through the `inertia_cable` gem. No custom ActionCable channels, and no record data in a broadcast.

**Backend:** Model broadcasts → `broadcasts_to` / `broadcast_refresh_to(self)` on `after_commit` (a refresh signal: the page reloads its props). The session and run lists get id-only row updates (`InertiaCable.broadcast(stream, { type: "session_update", id: id })`) and fetch the row back through their own authorized endpoint.
**Controller:** Pass `cable_stream: -> { inertia_cable_stream(record) }` prop.
**Frontend:** `useInertiaCableStream(cableStream, { only: ['tasks', 'columns'], enabled: !!board })`.

### Data Loading: Props First

Always prefer Inertia props over client-side `fetch()`. Data flows from controller through props. Exception: mutations (POST/PATCH/DELETE) use `apiFetch` + `router.reload` after success.

### Frontend: TypeScript/React

- Strict mode always enabled
- Base URL: `./app/frontend`, path alias `@/*`
- Mantine 9 for all UI components — never raw HTML elements for buttons, inputs, layout
- CSS Modules (`.module.css`) for custom styles, Mantine CSS variables for theming
- `usePage<PageProps>().props` to read Inertia props
- Persistent layouts via `setPageLayout(Page, persistentProjectLayout)` (`pages/Projects/ProjectLayout.tsx`); other signed-in pages render inside `<AuthLayout>`
- Forms: `@mantine/form` + `zod4Resolver` (from `mantine-form-zod-resolver`; the project is on zod 4) + `router.patch/post` for submission
- Inertia `useForm` for simple login-style forms
- `apiFetch` (shared/lib/apiFetch.ts) for JSON mutations — sets CSRF, Accept: json, credentials: include
- Typelizer-generated types in `types/generated/` — run `rails typelizer:generate` after changing Alba resources
- Tabler Icons (`@tabler/icons-react`) — not Mantine icons

### Frontend: Component Structure

Folders group code by product area and by resource — not one folder per component:

```
pages/<Area>/<Feature>/          # e.g. pages/Projects/Board/
  BoardPage.tsx                  # the Inertia page component
  BoardPage.module.css           # its CSS Module
  BoardPage.test.tsx             # its Vitest + Testing Library test
  GateStatusChip.tsx             # a component only this page uses, as a sibling file
  useBoardDnd.ts                 # hooks and helpers the same way
layouts/AuthLayout.tsx           # the signed-in shell
shared/
  ui/                            # app chrome and small primitives (AppSidebar, PageShell, PageHeader, …)
  components/                    # components several pages use (AssetPicker, SessionNewForm, …)
  resources/<resource>/          # resource-centric UI shared by company and project pages (agents/, tools/, …)
  lib/, lib/hooks/               # utilities and hooks (apiFetch, formatDate, useInertiaCableStream, …)
  theme/, analytics/             # Mantine theme; chart helpers
types/generated/                 # Typelizer output — regenerate, never edit
```

Rules:
- **One component per file**, named after the component; its `.module.css` and `.test.tsx` share the basename and sit beside it. A component with several parts may get its own folder (`shared/components/SessionShowContent/`).
- **Import the file itself** (`shared/components/AssetPicker`). The only barrels are `shared/ui/index.ts` and `shared/ui/sessions/index.ts`.
- **Start next to the page.** A component or hook lives beside the page that uses it; when a second page needs it, move it to `shared/components/` (or to `shared/resources/<resource>/` when it belongs to one resource).
- **Import direction:** pages import from `shared`, `layouts` and `types`; `shared` does not import from `pages`.

**Enforcement:** `make fsd` runs [steiger](https://github.com/feature-sliced/steiger) against
`app/frontend` (config: `steiger.config.js`) and is part of `make fe_check` / `check_all`. The
config disables the vanilla-FSD rules that fight this loose interpretation (segmentless pages,
per-segment barrels, the `shared/components` segment name); the layer boundary rules (import
direction, cross-slice access, reserved names) stay on.

### Container Strategy Pattern

When adding a new strategy:
1. Inherit from `BaseStrategy` (or `AgentBaseStrategy` for agents)
2. Implement `resolve_image`, `before_create_container`
3. Override phase methods as needed
4. Register in `PhaseActivity#resolve_strategy` if new trigger type

When adding a new agent runtime:
1. Create adapter in `app/services/agents/`
2. Implement: `config_path`, `home_dir`, `auth_required_keys`, `generate_config`, `extract_credentials`
3. Register it in `AgentCredentialsService::ADAPTERS`, `CompanyMembership::AVAILABLE_AGENTS`, and `ContainerStrategies::AgentBaseStrategy` (`VALID_AGENT_TYPES`, `AUTH_COMMANDS`, `SESSION_COMMANDS`)
4. Add its image: `docker/<runtime>/`, the `build-agents` target in the `Makefile`, `.github/workflows/images.yml`
5. Document it in `docs/user-guide/runtimes.md` (and the portal copy) — `test/docs/documentation_drift_test.rb` fails until every runtime is there

The full touch-point list, frontend included, is in the Kiro CLI research report (`docs/planning-artifacts/research/technical-kiro-cli-as-a-platform-agent-runtime-research-2026-08-28.md`).

### Container Runtime

Runtime selected by `Settings.container_runtime` (`CONTAINER_RUNTIME`: `kubernetes` or `k8s` selects Kubernetes, anything else Docker). Docker is the local-development runtime; production runs Kubernetes.

Both runtimes' `exec` return `[stdout, stderr, exit_code]` with stdout and stderr as arrays of strings. Use `exec!` where "the container is gone" must not read as "the command failed": on Kubernetes it raises `ContainerRuntime::ContainerUnreachableError` instead of returning exit code 1 (Docker answers as `exec` does).

---

## Testing

Read [docs/testing.md](../testing.md) before writing a test — it is the doctrine (what to test at which layer, the mocking rules, the blessed fakes). The helpers used most:

- **Request tests** (new controllers): `ActionDispatch::IntegrationTest` + `sign_in_as(user)` (`test/support/auth_helper.rb`, posts the real login form); `assert_inertia_page` / `assert_inertia_props` for Inertia pages (`require "inertia_rails/minitest"` is in `test/test_helper.rb`)
- **Legacy API controller tests:** `ActionController::TestCase` defaults to `format: :json`; `sign_in(user)` writes `session[:user_id]`; JSON body via `response.parsed_body` or `body` (a `Hashie::Mash`)
- **Admin tests:** `Admin::ActionControllerTestCase` defaults to `format: :html`
- **Container runtimes:** `stub_container_runtime` (`test/support/stub_support.rb`) injects `ContainerRuntime::FakeRuntime`
- **Temporal:** `TemporalHelper` (`mock_temporal_start`), `run_workflow`, `run_activity`
- **End to end:** Capybara + Cuprite in `test/system/`, SitePrism page objects in `test/system/pages/`
- The backend suite runs in parallel (one worker and database per core); never run two backend suites against the same Postgres at once

## Anti-Patterns

- **Never write `encrypted_config_data` directly** — always use `config_data=` setter
- **Never use plain Hash/Array props when defer props exist on the same page** — wrap in `-> { }`
- **Never use ActiveRecord enums** — use `enumerize`
- **Never use fixtures** — use factory_bot factories
- **Never use custom ActionCable channels** — use Inertia Cable (`broadcasts_to` / `broadcast_refresh_to`, or an id-only row update)
- **Never use client-side fetch for data that should be Inertia props** — data flows from controller
- **Never use `router.reload` for drawer open/close** — use `router.get` (updates URL)
- **Never use `update_column` without explicit `broadcast_refresh_to`** — bypasses after_commit
- **Never add a second UI kit, a client-side store, a client router, or another form library** — Mantine, Inertia props, Inertia routing, and Mantine Form cover them
- **Never use `as_json` or inline hashes for records in Inertia props** — use Alba resources; hand-built hashes bypass type generation
- **Never forget `company_id` filter** in multi-tenant queries
- **Never read `ENV[...]` from app code** — add the key to `config/settings.yml` and read `Settings.*` (pre-Settings boot files are the only exception)
- **Never skip `frozen_string_literal: true`** in Ruby files
- **Never use `new Date()` on Alba-serialized dates** — use `shared/lib/formatDate` helpers

---

## Key File Locations

```
app/
  controllers/
    web/                                # Inertia HTML app
      company/                          # Company-scoped (Pundit, auth required)
        projects/                       # Project-scoped (current_project, inertia_share project)
          boards_controller.rb          # Kanban board
          workflows_controller.rb       # Workflow CRUD
          sessions_controller.rb        # Terminal sessions
    api/v1/                             # JSON API
      internal/                         # ws_auth, usage_statistics
    admin/                              # Administrate panel
    webhooks/                           # GitHub, GitLab, Azure DevOps, Slack, generic ingress
    concerns/                           # auth, authorization, pagination
    mcp_controller.rb                   # /mcp — session keys and personal MCP tokens
  models/                               # ActiveRecord models
  resources/                            # Alba resources (ApplicationResource subclasses)
    application_resource.rb             # Base: Alba::Resource + Typelizer::DSL + transform_keys :lower_camel
  lib/deep_key_camelizer.rb             # Camelizes every Inertia prop (installed in config/initializers/inertia.rb)
  services/
    agents/                             # Agent adapters (per-agent logic)
    container_strategies/               # Strategy pattern (auth, session, tool)
    container_runtime/                  # Runtime implementations (docker, k8s)
    container_runtime.rb                # Runtime factory
    container_service.rb                # Phase runner
    agent_credentials_service.rb        # Agent credential facade
    session_context_service.rb          # Session config injection
    temporal_service.rb                 # Temporal client
    internal_tools/                     # Session tools (board, workflow, Slack, Coder, Azure DevOps, …)
    personal_tools/                     # Personal MCP tools (also the Aixle Builder's tools)
    tools/                              # Tool registry, MCP request handlers, BuilderToolset
    context_builders/                   # Context assembly
  contexts/                             # Pundit policy contexts (BaseContext, ProjectContext)
  policies/                             # Pundit policies
  temporal/
    workflows/                          # Temporal workflows
    activities/                         # Temporal activities
    schedules.yml                       # Periodic sweeps and syncs
  frontend/
    entrypoints/
      application.tsx                   # createInertiaApp + MantineProvider + Sentry
    pages/                              # Route-mapped screens (slice-by-feature)
      Projects/                         # Board, Workflows, Sessions, Settings, etc.
      Company/                          # Members, Sessions, Settings, Assets, Analytics, WorkflowCatalog
      Auth/                             # Login
      Profile/                          # User profile
      Onboarding/                       # Onboarding flow
    layouts/
      AuthLayout.tsx                    # Signed-in shell (sidebar, header, flash)
    shared/
      routes.ts                         # Auto-generated by ts_routes gem (app/frontend/shared/routes.ts)
      ui/                               # App chrome and primitives (AppSidebar, PageShell, PageHeader, …)
      ui/types.ts                       # SharedProps, SharedProject, SharedSettings
      components/                       # Cross-feature components
      resources/                        # Resource-centric UI (agents/, tools/, etc.)
      lib/
        apiFetch.ts                     # Fetch wrapper (CSRF, JSON, credentials)
        hooks/useInertiaCableStream.ts  # Cable stream hook
        sentry.ts                       # Sentry init
        formatDate.ts                   # Date formatting helpers
      theme/mantineTheme.ts             # Mantine theme config
    types/generated/                    # Typelizer output (auto-generated TS interfaces)

config/
  initializers/typelizer.rb             # Typelizer config (output_dir, camelCase)

test/
  integration/                          # Request tests (web/, api/, webhooks/, personal MCP, container callbacks)
  controllers/                          # Legacy API/Admin controller tests
  system/                               # Capybara + Cuprite end-to-end tests; pages/ holds SitePrism page objects
  docs/                                 # Documentation drift checks
  support/
    auth_helper.rb                      # sign_in, sign_out, sign_in_as
    stub_support.rb                     # stub_container_runtime → ContainerRuntime::FakeRuntime
    fakes/                              # Canonical fakes (runtime, GitHub, GitLab, Slack, Azure DevOps, …)
    upload_support.rb                   # File upload test helpers
  helpers/
    temporal_helper.rb                  # Temporal test helpers
  factories/                            # FactoryBot factories

docs/                                   # Architecture & design docs (see docs/index.md)
  architecture/                         # Architecture decisions
  design/                               # System design docs (workflows, tools, sessions, BMAD)
  project/                              # Project overview + this LLM context file
  research/                             # Technical research + design docs
  specs/                                # Feature specs (frozen-intent format)
  strategy/                             # Business/open-source strategy docs
```

---

## Key Terminology

| Term | Meaning | DB column | Examples |
|------|---------|-----------|----------|
| **Agent Runtime** | Which AI agent CLI to use | `workflow_runs.agent_runtime`, `terminal_sessions.agent_type` | `claude_code`, `cursor_cli`, `codex`, `gemini_cli`, `antigravity_cli`, `grok`, `kiro_cli` |
| **Container Runtime** | Infrastructure that runs containers | `ContainerRuntime.build` (code-level) | Docker (local development), Kubernetes (production) |
| **Internal Tool** | Platform tool defined in code (`Tools::Registry`), runs in-process | `tools.source = 'code'`, `execution_mode = 'app'` | `list_sub_steps`, `slack_post_message`, `board_*`, `coder_*` |
| **Workflow Tool** | Internal tool needing workflow context, auto-injected via code-only `inject_when` rules | `Tools::Registry` `inject_when` (no DB column) | `list_sub_steps`, `mark_sub_step`, `finish_session`, `fail_session` |
| **Builder Tool** | Personal MCP tools served inside an Aixle Builder session, pinned to its project and run as its user | `Tools::BuilderToolset` (no rows) | `create_workflow`, `create_workflow_trigger`, `validate_workflow` |
| **Custom Tool** | User-created tool in Docker container | `tools.source = 'db'`, `execution_mode = 'container'` | Company- or project-scoped |
| **Alba Resource** | Serializer for Inertia props + JSON | `app/resources/` | `BoardTaskResource`, `ProjectResource` |
| **Inertia Cable** | Real-time prop refresh via ActionCable | `broadcasts_to` / `broadcast_refresh_to` | Board live updates |
| **Shared Props** | Auto-injected Inertia props | `inertia_share` | `current_user`, `projects`, `flash`, `settings`, `permissions`, `project` |

### Tool visibility rules
- **Auto-injected internal tools** are pulled in by code-only `inject_when` rules in `Tools::Registry` (e.g. workflow-step sessions get `list_sub_steps`/`mark_sub_step`/`finish_session`/`fail_session`)
- **Other internal tools** (e.g. `slack_post_message`) appear only when explicitly added to `session.tools`; integration-gated ones are hidden until the integration is connected (`requires_integration`)
- **Custom tools** come from `session.tools`; fallback to project-level tools if none explicitly selected
- **Picker visibility** is `Tool.visible_for_project` / `visible_for_company` — non-attachable tools (`user_attachable: false`) are excluded
- **Builder sessions** additionally get `Tools::BuilderToolset`: the personal MCP tools that take a `project_id`, served by the session's own MCP endpoint with `project_id` filled in and every lookup pinned to the session's project

