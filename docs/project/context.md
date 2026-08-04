---
project_name: 'aixle'
date: '2026-04-09'
status: 'complete'
optimized_for_llm: true
---

# Project Context for AI Agents

_Critical rules and patterns for implementing code in this project._

---

## Technology Stack

**Core:**
- **Backend:** Ruby on Rails 8.1, Ruby 4.0.5
- **Frontend:** React 19.2, TypeScript 5.9
- **Bridge:** Inertia.js 3.0 (inertia_rails 3.19 + @inertiajs/react 3.0.1)
- **UI:** Mantine 9.4 (core, dates, form, hooks, modals, notifications) + Tabler Icons
- **Database:** PostgreSQL 15 (citext, plpgsql)
- **Cache:** Redis
- **Orchestration:** Temporal (temporalio gem)
- **Build:** Vite 8.1 + vite-plugin-ruby 5.2

**Key Dependencies:**
- **Serialization:** Alba 3.10 + Typelizer 0.12 (auto-generated TS types)
- **Forms:** @mantine/form + Zod + mantine-form-zod-resolver; Inertia useForm for simple cases
- **Real-time:** Inertia Cable (@inertia-cable/react + inertia_cable gem) + ActionCable transport
- **Tables:** @tanstack/react-table 8.21
- **DnD:** @dnd-kit/core 6.3 + @dnd-kit/sortable 10.0
- **Auth:** OmniAuth (Google) + Pundit + has_secure_password (no Devise)
- **Storage:** Shrine 3.8 + AWS S3 + Uppy (frontend uploads)
- **Container (Docker):** docker-api 2.3
- **Container (K8s):** kubeclient 4.13 + websocket-client-simple
- **MCP:** mcp 0.22.0
- **Enums:** enumerize gem (NOT ActiveRecord enums)
- **State machines:** aasm gem
- **Pagination:** Pagy
- **Search/Filter:** Ransack
- **Monitoring:** Sentry (sentry-ruby, sentry-rails, @sentry/react)
- **Code editor:** CodeMirror (@uiw/react-codemirror)
- **Terminal:** xterm.js 6.0
- **Charts:** Recharts 3.8
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
| **Inertia props** | `InertiaRails.config.prop_transformer` (`camelize(:lower)`) | snake_case → camelCase |
| **Alba resources** | `ApplicationResource` has `transform_keys :lower_camel` | snake_case → camelCase |
| **Typelizer types** | `properties_transformer` (`camelize(:lower)`) | snake_case → camelCase |

**CRITICAL:** `wrap_parameters false` is set on `Web::ApplicationController`. Without it, Rails `ParamsWrapper` auto-adds an empty wrapper key that collides with the underscored camelCase key.

### Controller Hierarchy

```
ApplicationController (underscore_params, gon_settings)
├── Web::ApplicationController (AuthConcern, wrap_parameters false, inertia_share: current_user, projects, flash)
│   ├── Web::Company::ApplicationController (Pundit, AuthorizationConcern, layout "inertia", require_auth)
│   │   └── Web::Company::Projects::ApplicationController (set_project, inertia_share: project)
│   │       └── Feature controllers (boards, workflows, sessions, etc.)
│   ├── Web::SessionsController (login/logout)
│   ├── Web::ProfileController
│   └── Web::OnboardingController
├── Api::V1::ApplicationController (JSON, Pundit, PaginationConcern, skip CSRF, authenticate_user!)
│   ├── Api::V1::Internal:: (ws_auth, usage_statistics)
│   └── Api::V1::AssetsController (presign, upload)
├── Admin::ApplicationController (Administrate, authenticate_admin!)
└── Webhooks:: (GitHub, GitLab — HMAC/secret verification)
```

### Serialization: Alba Resources Only (for Inertia)

All Inertia props go through Alba resources (`ApplicationResource` subclasses). AMS (`ActiveModel::Serializers`) is legacy — only used in some workflow/step JSON endpoints.

```ruby
# ✅ Inertia page
render inertia: "Sessions/ShowPage", props: {
  session: -> { TerminalSessionResource.new(session).to_h }
}

# ✅ JSON API (same resource)
render json: TerminalSessionResource.new(session).to_h

# ❌ NEVER for Inertia — bypass type generation, keys not transformed
render inertia: "Page", props: { session: { id: session.id } }
```

### Shared Props (Auto-Injected)

`Web::ApplicationController` injects `current_user`, `projects`, `flash` via `inertia_share`.
`Web::Company::Projects::ApplicationController` adds `project`.

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
- `BaseAdapter` → `ClaudeCodeAdapter` / `CursorCliAdapter` / `CodexAdapter` / `GeminiCliAdapter`

**Phases:** `pull_image → create_container → start_container → exec → cleanup`

### Multi-tenancy & Scoping

Polymorphic `scope` (Company or Project) used by: Agent, Tool, MCPServer, Skill, Asset, ConfigItem, Repository.

Pattern: `visible_for_project(project)` → unions code/platform + company-scoped + project-scoped rows. No name-level override; System-scoped and non-attachable meta/Builder rows are excluded via `user_attachable`. (`visible_for_company` is the company-level analogue.)

### Encrypted Fields

- `AgentCredential#config_data` — uses `encryptor.encrypt_and_sign` / `decrypt_and_verify`
- `Integration#credentials` — encrypted
- `ConfigItem#encrypted_value` — for secrets

**Important:** Always use setter (`config_data=`) to write, never write `encrypted_config_data` directly.

### TerminalSession State Machine

```
not_started → running → ready → finished
                    ↘ failed ↙
```

Events: `start!`, `mark_ready!`, `finish!`, `fail!`

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
- Authorization: Pundit policies for all resources, `BaseContext` as policy context
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

All real-time updates use `inertia_cable` gem via `broadcast_refresh_to`. No custom ActionCable channels.

**Backend:** Model broadcasts → `broadcast_refresh_to(self)` on `after_commit`.
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
- Persistent layouts via `(Page as any).layout = persistentProjectLayout`
- Forms: `@mantine/form` + `zodResolver` + `router.patch/post` for submission
- Inertia `useForm` for simple login-style forms
- `apiFetch` (shared/lib/apiFetch.ts) for JSON mutations — sets CSRF, Accept: json, credentials: include
- Typelizer-generated types in `types/generated/` — run `rails typelizer:generate` after changing Alba resources
- Tabler Icons (`@tabler/icons-react`) — not Mantine icons

### Frontend: Component Structure (FSD-style segments)

Every non-trivial component lives in its own folder with explicit segments:

```
ComponentName/
  index.ts              # Public API — re-exports component (and types if needed)
  ComponentName.tsx     # Component implementation
  ComponentName.module.css  # Scoped styles (CSS Modules)
```

Rules:
- **One component = one folder.** Never put multiple components in a single file.
- **`index.ts` is the barrel** — external code imports from the folder, never from the `.tsx` file directly.
- **CSS Modules co-located** — styles live next to the component, named `ComponentName.module.css`.
- **Pages follow the same pattern** — `pages/Projects/Board/BoardPage.tsx` + `BoardPage.module.css` in the same folder.
- Shared components: `shared/components/ComponentName/index.ts` + `ComponentName.tsx` + `ComponentName.module.css`.
- Feature-local components: co-located inside the page folder (e.g. `pages/Projects/Board/TaskCard/`).
- **Private sub-components** live in a `components/` folder inside the parent:

```
BoardPage/
  index.ts
  BoardPage.tsx
  BoardPage.module.css
  components/                       # Private to BoardPage — not imported from outside
    TaskCard/
      index.ts
      TaskCard.tsx
      TaskCard.module.css
    ColumnHeader/
      index.ts
      ColumnHeader.tsx
      ColumnHeader.module.css
```

- If a sub-component starts being used outside its parent, promote it to `shared/components/`.

### Container Strategy Pattern

When adding a new strategy:
1. Inherit from `BaseStrategy` (or `AgentBaseStrategy` for agents)
2. Implement `resolve_image`, `before_create_container`
3. Override phase methods as needed
4. Register in `PhaseActivity#resolve_strategy` if new trigger type

When adding a new agent adapter:
1. Create adapter in `app/services/agents/`
2. Implement: `config_path`, `home_dir`, `auth_required_keys`, `generate_config`, `extract_credentials`
3. Register in `AgentCredentialsService::ADAPTERS`
4. Add Docker image configuration

### Container Runtime

Runtime selected by `Settings.container_runtime` ("docker" or "kubernetes").

Key difference: Docker exec returns `[[stdout], [stderr], exit_code]`, K8s exec returns `[stdout, stderr, exit_code]`.

---

## Testing

### Backend (Minitest)

- Tests in `test/` directory
- `require "inertia_rails/minitest"` for Inertia assertions
- **Integration tests** (Inertia pages): inherit `WebTestCase < ActionDispatch::IntegrationTest`
  - `create_authenticated_user` → returns `[company, user]` with `:onboarding_completed` trait
  - `web_sign_in(user)` → `post login_path` with password
  - Assert: `assert_inertia_component "Projects/Board/BoardPage"`
- **Controller tests** (API): `ActionController::TestCase` defaults to `format: :json`
  - `sign_in(user)` → sets `session[:user_id]`
  - JSON body: `response.parsed_body` or `Hashie::Mash.new(JSON.parse(response.body))`
- **Admin tests:** `Admin::ActionControllerTestCase` defaults to `format: :html`
- `test/support/stub_support.rb` — reusable stubs for Docker/K8s runtimes
- `test/support/auth_helper.rb` — `sign_in`, `sign_out`, `sign_in_as`
- Integration container tests: `test/integration/container_workflow_integration_test.rb`

## Anti-Patterns

- **Never write `encrypted_config_data` directly** — always use `config_data=` setter
- **Never use plain Hash/Array props when defer props exist on the same page** — wrap in `-> { }`
- **Never use ActiveRecord enums** — use `enumerize`
- **Never use fixtures** — use factory_bot factories
- **Never use custom ActionCable channels** — use Inertia Cable (`broadcast_refresh_to`)
- **Never use client-side fetch for data that should be Inertia props** — data flows from controller
- **Never use `router.reload` for drawer open/close** — use `router.get` (updates URL)
- **Never use `update_column` without explicit `broadcast_refresh_to`** — bypasses after_commit
- **Never use Material UI, Redux, TanStack Router, or React Hook Form** — removed from stack
- **Never use AMS for Inertia props** — use Alba resources with Typelizer
- **Never use `as_json` or inline hashes for Inertia props** — bypass type generation
- **Never forget `company_id` filter** in multi-tenant queries
- **Never read `ENV[...]` from app code** — add the key to `config/settings.yml` and read `Settings.*` (pre-Settings boot files are the only exception)
- **Never skip `frozen_string_literal: true`** in Ruby files
- **Never use `new Date()` on Alba-serialized dates** — use `shared/lib/formatDate` helpers
- **Container exec format differs between runtimes** — Docker: `[[stdout], [stderr], exit_code]`, K8s: `[stdout, stderr, exit_code]`

---

## Key File Locations

```
app/
  controllers/
    web/                                # Inertia HTML app
      company/                          # Company-scoped (Pundit, auth required)
        projects/                       # Project-scoped (set_project, inertia_share project)
          boards_controller.rb          # Kanban board
          workflows_controller.rb       # Workflow CRUD
          sessions_controller.rb        # Terminal sessions
    api/v1/                             # JSON API
      internal/                         # ws_auth, usage_statistics
    admin/                              # Administrate panel
    webhooks/                           # GitHub, GitLab webhooks
    concerns/                           # auth, authorization, pagination, steps_actions
  models/                               # ActiveRecord models
  resources/                            # Alba serializers (ApplicationResource subclasses)
    application_resource.rb             # Base: Alba::Resource + Typelizer::DSL + transform_keys :lower_camel
  serializers/                          # Legacy AMS (workflow/step JSON only)
  services/
    agents/                             # Agent adapters (per-agent logic)
    container_strategies/               # Strategy pattern (auth, session, tool)
    container_runtime/                  # Runtime implementations (docker, k8s)
    container_runtime.rb                # Runtime factory
    container_service.rb                # Phase runner
    agent_credentials_service.rb        # Agent credential facade
    session_context_service.rb          # Session config injection
    temporal_service.rb                 # Temporal client
    internal_tools/                     # Board/meta tools
    context_builders/                   # Context assembly
  contexts/                             # Pundit policy contexts (BaseContext)
  policies/                             # Pundit policies
  temporal/
    workflows/                          # Temporal workflows
    activities/                         # Temporal activities
  frontend/
    entrypoints/
      application.tsx                   # createInertiaApp + MantineProvider + Sentry
    pages/                              # Route-mapped screens (slice-by-feature)
      Projects/                         # Board, Workflows, Sessions, Settings, etc.
      Company/                          # Members, Integrations, Agents, etc.
      Auth/                             # Login
      Profile/                          # User profile
      Onboarding/                       # Onboarding flow
    layouts/
      AuthLayout.tsx                    # Signed-in shell (sidebar, header, flash)
      GuestLayout.tsx                   # Unauthenticated shell
    shared/
      routes.ts                         # Auto-generated by ts_routes gem (app/frontend/shared/routes.ts)
      ui/                               # App chrome (AppSidebar, AppHeader, PageShell)
      ui/types.ts                       # SharedProps, SharedUser, SharedProject
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
  integration/
    web_test_case.rb                    # Base for Inertia integration tests
    web/company/                        # Company controller tests
    web/company/projects/               # Project controller tests
  controllers/                          # API/Admin controller tests
  support/
    auth_helper.rb                      # sign_in, sign_out, sign_in_as
    stub_support.rb                     # Reusable runtime stubs
    upload_support.rb                   # File upload test helpers
  helpers/
    temporal_helper.rb                  # Temporal test helpers
  factories/                            # FactoryBot factories
  playwright/                           # E2E test helpers

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
| **Agent Runtime** | Which AI agent CLI to use | `workflow_runs.agent_runtime`, `terminal_sessions.agent_type` | `claude_code`, `cursor_cli`, `codex`, `gemini_cli` |
| **Container Runtime** | Infrastructure that runs containers | `ContainerRuntime.build` (code-level) | Docker (local), Kubernetes (cluster) |
| **Internal Tool** | Platform tool defined in code (`Tools::Registry`), runs in-process | `tools.source = 'code'`, `execution_mode = 'app'` | `list_sub_steps`, `slack_post_message`, `board_*`, `coder_*` |
| **Workflow Tool** | Internal tool needing workflow context, auto-injected via code-only `inject_when` rules | `Tools::Registry` `inject_when` (no DB column) | `list_sub_steps`, `mark_sub_step`, `finish_session`, `fail_session` |
| **Builder/meta Tool** | Aixle Builder meta tools, hidden from pickers | `tools.source = 'code'`, `user_attachable = false` | `meta_create_workflow`, `meta_link_resource_to_step` |
| **Custom Tool** | User-created tool in Docker container | `tools.source = 'db'`, `execution_mode = 'container'` | Company- or project-scoped |
| **Alba Resource** | Serializer for Inertia props + JSON | `app/resources/` | `BoardTaskResource`, `ProjectResource` |
| **Inertia Cable** | Real-time prop refresh via ActionCable | `broadcast_refresh_to` | Board live updates |
| **Shared Props** | Auto-injected Inertia props | `inertia_share` | `current_user`, `projects`, `flash`, `project` |

### Tool visibility rules
- **Auto-injected internal tools** are pulled in by code-only `inject_when` rules in `Tools::Registry` (e.g. workflow-step sessions get `list_sub_steps`/`mark_sub_step`/`finish_session`/`fail_session`)
- **Other internal tools** (e.g. `slack_post_message`) appear only when explicitly added to `session.tools`; integration-gated ones are hidden until the integration is connected (`requires_integration`)
- **Custom tools** come from `session.tools`; fallback to project-level tools if none explicitly selected
- **Picker visibility** is `Tool.visible_for_project` / `visible_for_company` — non-attachable meta/Builder tools (`user_attachable: false`) are excluded

---

**Last Updated:** 2026-04-09
