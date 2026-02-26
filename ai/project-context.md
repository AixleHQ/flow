---
project_name: 'palad'
date: '2026-02-21'
status: 'complete'
optimized_for_llm: true
---

# Project Context for AI Agents

_Critical rules and patterns for implementing code in this project._

---

## Technology Stack

**Core:**
- **Backend:** Ruby on Rails 8.1.2, Ruby 3.4.0
- **Frontend:** React 19.0.0, TypeScript 5.9.3
- **Database:** PostgreSQL 15.3
- **Cache:** Redis 7.2
- **Orchestration:** Temporal (temporalio gem)
- **Build:** Vite 7.3.1
- **UI:** Material UI 6.x

**Key Dependencies:**
- **Routing:** TanStack Router
- **State:** Redux Toolkit (global) + Zustand (local)
- **Forms:** React Hook Form + Zod
- **Auth:** OmniAuth (Google) + Pundit
- **Storage:** Shrine 3.6 + AWS S3
- **Container (Docker):** docker-api 2.3
- **Container (K8s):** kubeclient 4.13 + websocket-client-simple
- **MCP:** actionmcp 0.100, solid_mcp
- **Enums:** enumerize gem (NOT ActiveRecord enums)
- **State machines:** aasm gem

---

## Architecture Patterns

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

Pattern: `merged_for_project(project)` → returns internal + company + project resources, project overrides company by name.

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

`session.strategy` returns the correct Strategy instance based on `session_type`.

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
- API responses: wrap lists in `items`, single resources in `data`
- Authorization: Pundit policies for all resources
- Serializers: ActiveModelSerializers

### Container Strategy Pattern

When adding a new strategy:
1. Inherit from `BaseStrategy` (or `AgentBaseStrategy` for agents)
2. Implement `resolve_image`, `before_create_container`
3. Override phase methods as needed (`start_container`, `exec`, `before_cleanup`)
4. Register in `PhaseActivity#resolve_strategy` if new trigger type

When adding a new agent:
1. Create adapter in `app/services/agents/`
2. Implement: `config_path`, `home_dir`, `auth_required_keys`, `generate_config`, `extract_credentials`
3. Register in `AgentCredentialsService::ADAPTERS`
4. Add Docker image configuration

### Container Runtime

Runtime is selected by `Settings.container_runtime` ("docker" or "kubernetes").

Docker: uses `Docker::Image`, `Docker::Container` from docker-api gem.
Kubernetes: uses `Kubeclient::Client` for core API + Traefik CRDs, `WebSocket::Client::Simple` for exec.

Key difference: Docker exec returns `[[stdout], [stderr], exit_code]`, K8s exec returns `[stdout, stderr, exit_code]`.

### Testing

**Backend (Minitest):**
- Tests in `test/` directory
- `test/support/stub_support.rb` — reusable stubs for Docker/K8s runtimes
- Integration tests: `test/integration/container_workflow_integration_test.rb` — 36 combinatorial tests
- Use `docker exec app-web-1 bundle exec rails test` to run inside container

**Frontend (Vitest):**
- Co-located tests `*.test.tsx`
- Mock API calls and external deps

### TypeScript/Frontend

- Strict mode always enabled
- Base URL: `./app/frontend`
- Import order: builtin → external → internal → parent → sibling
- `camelcaseKeys`/`decamelizeKeys` for API request/response
- Feature-Sliced Design: app → pages → features → entities → shared
- Redux Toolkit for API cache + global state, Zustand for local component state
- React Hook Form + Zod validation (on blur + on submit)

---

## Anti-Patterns

- **Never write `encrypted_config_data` directly** — always use `config_data=` setter
- **Never mix naming conventions** — snake_case in Ruby, camelCase in TypeScript
- **Never forget `company_id` filter** in multi-tenant queries
- **Never use ActiveRecord enums** — use `enumerize`
- **Never use fixtures** — use factory_bot factories
- **Never stub Mocha `.returns` with a block for dynamic responses** — use `define_singleton_method` on Object.new instead
- **Never skip `frozen_string_literal: true`** in Ruby files
- **Container exec format differs between runtimes** — Docker: `[[stdout], [stderr], exit_code]`, K8s: `[stdout, stderr, exit_code]`

---

## Key File Locations

```
app/
  models/                              # ActiveRecord models
  services/
    agents/                            # Agent adapters (per-agent logic)
    container_strategies/              # Strategy pattern (auth, session, tool)
    container_runtime/                 # Runtime implementations (docker, k8s)
    container_runtime.rb               # Runtime factory
    container_service.rb               # Phase runner
    agent_credentials_service.rb       # Agent credential facade
    session_context_service.rb         # Session config injection
    temporal_service.rb                # Temporal client
  temporal/
    workflows/                         # Temporal workflows
    activities/                        # Temporal activities
  controllers/
    api/v1/                            # Public API
    api/v1/company/                    # Company-scoped API
    api/v1/company/projects/           # Project-scoped API
    api/v1/internal/                   # Internal endpoints (ws_auth, usage)
    admin/                             # Administrate panel
  channels/                            # ActionCable (TerminalSessionChannel)

test/
  support/stub_support.rb             # Reusable runtime stubs
  integration/                         # Integration tests
  factories/                           # FactoryBot factories

ai/                                    # AI planning & architecture docs
  architecture/                        # Architecture decisions
  epics/                               # Epic definitions
  prd/                                 # Product requirements
```

---

## Key Terminology

| Term | Meaning | DB column | Examples |
|------|---------|-----------|----------|
| **Agent Runtime** | Which AI agent CLI to use for execution | `workflow_runs.agent_runtime`, `terminal_sessions.agent_type` | `claude_code`, `cursor_cli`, `codex`, `gemini_cli` |
| **Container Runtime** | Infrastructure that runs agent containers | `ContainerRuntime.build` (code-level) | Docker (local), Kubernetes (cluster) |
| **Internal Tool** | System-provided tool, runs in-process (no Docker) | `tools.kind = 'internal'` | `code_climate`, `list_sub_steps` |
| **Workflow Tool** | Internal tool requiring workflow context (`step_run`), auto-injected into `workflow_step` sessions | `tools.workflow_only = true` | `list_sub_steps`, `mark_sub_step`, `write_step_note` |
| **Custom Tool** | User-created tool that runs in a Docker container | `tools.kind = 'custom'` | Company or project scoped |

### Tool visibility rules
- **Workflow-only tools** (`workflow_only: true`) are auto-injected into `workflow_step` sessions only
- **Other internal tools** (e.g. `code_climate`) appear only when explicitly added to `session.tools`
- **Custom tools** come from `session.tools`; fallback to project-level tools if none explicitly selected

---

**Last Updated:** 2026-02-22
