# Architecture Decision Document

**Updated:** 2026-02-21

## Table of Contents

- [Core Architectural Decisions](./core-decisions.md)
  - [Data Architecture](./core-decisions.md#data-architecture)
  - [Authentication & Security](./core-decisions.md#authentication-security)
  - [API & Communication Patterns](./core-decisions.md#api-communication-patterns)
  - [Frontend Architecture](./core-decisions.md#frontend-architecture)
  - [Infrastructure & Deployment](./core-decisions.md#infrastructure-deployment)
- [Implementation Patterns & Consistency Rules](./implementation-patterns.md)

## Container Execution Architecture

Core pattern: **PhaseActivity → ContainerService → Strategy → Runtime**

### Strategies (what to do)

| Strategy | Inherits | Purpose |
|----------|----------|---------|
| `BaseStrategy` | — | Abstract base: phase hooks, container lifecycle |
| `AgentBaseStrategy` | BaseStrategy | Shared agent logic: image resolution, env vars, ttyd, ports |
| `AgentAuthStrategy` | AgentBaseStrategy | OAuth credential collection via file watching |
| `AgentSessionStrategy` | AgentBaseStrategy | Interactive/non-interactive sessions, log/usage collection |
| `WorkflowStepStrategy` | AgentSessionStrategy | Agent session bound to a workflow step |
| `ToolStrategy` | BaseStrategy | Base for tool execution: command, wait for exit, timeout |
| `CustomToolStrategy` | ToolStrategy | User-defined Docker-based custom tool execution |
| `InternalToolStrategy` | ToolStrategy | Platform-provided (code-source) tool execution |

### Runtimes (where to run)

| Runtime | Backend | Key Differences |
|---------|---------|-----------------|
| `DockerRuntime` | docker-api gem | exec returns `[[stdout], [stderr], exit_code]`; uses Docker::Container |
| `KubernetesRuntime` | kubeclient + websocket | exec returns `[stdout, stderr, exit_code]`; uses Pods + Services + IngressRoutes |

Runtime selected via `Settings.container_runtime` ("docker" or "kubernetes").

### Agent Adapters

| Adapter | Agent | Auth Path | Usage Method |
|---------|-------|-----------|-------------|
| `ClaudeCodeAdapter` | Claude Code | `/home/claude/.claude.json` | OTLP telemetry |
| `CursorCliAdapter` | Cursor CLI | `/home/cursor/.config/cursor/auth.json` | MITM logs → Cursor API |
| `CodexAdapter` | Codex | `/home/codex/.codex/auth.json` | MITM logs (SSE parsing) |
| `GeminiCliAdapter` | Gemini CLI | `/home/gemini/.gemini/oauth_creds.json` | OTLP telemetry |

### Container Lifecycle Phases

```
pull_image → create_container → start_container → exec → cleanup
```

Each phase calls: `before_X(**state)` → `X(**state)` → `after_X(**state)`

ContainerService merges returned hashes into shared state between phases.

## Temporal Workflows

| Workflow | Trigger | Phases |
|----------|---------|--------|
| `ContainerWorkflow` | API (session/tool create) | Full container lifecycle with signal support |
| `StaleSessionCleanupWorkflow` | Hourly cron | Cleanup running >30min, ready >25h sessions |
| `DismissedAssetCleanupWorkflow` | Daily 3AM cron | Remove dismissed assets after 7-day grace |

### Error Handling

- [Temporal Error Handling](./temporal-error-handling.md) — retryable vs non-retryable, benign exceptions
- `TemporalExceptions.wrap(error, retryable:, benign:)` — wraps into `Temporalio::Error::ApplicationError`
- `PhaseError` (from ContainerService) → non-retryable
- `Docker::Error::DockerError` → retryable

## Multi-tenancy

Polymorphic `scope` (Company or Project): Agent, Tool, Workflow, MCPServer, Skill, Asset, ConfigItem, Repository.

Visibility scopes: `Model.visible_for_project(project)` and `Model.visible_for_company(company)` (plus `for_project`/`for_company` for a single scope). `visible_for_project` is a union of Company-scoped and Project-scoped rows (System-scoped rows excluded); `visible_for_company` returns Company-scoped rows. No name-based override between scopes.

## Data Model Highlights

- **TerminalSession** — AASM state machine, links to User + Project + `configured_agent` (Agent), stores token usage
- **AgentCredential** — encrypted config per user/agent, `config_data=` setter encrypts, `config_data` getter decrypts
- **Tool** — custom Docker-based tools, scoped, with ToolFiles and parameters
- **SessionLog** — Shrine-attached log files per session
- **UsageStatistic** — per-session token breakdown and cost

## API Architecture

- Controller patterns and authorization are documented in [Implementation Patterns](./implementation-patterns.md#api-controller-patterns)
- Controller hierarchy: `ApplicationController` → `Api::V1::ApplicationController` (declares `dynamic_authorize!`). Company controllers (e.g. `Api::V1::Company::AssetsController`) inherit directly from `Api::V1::ApplicationController` and define `current_company` inline; `current_project` lives in `Api::V1::Projects::ApplicationController`.
- Authorization: Pundit policies + `AuthorizationConcern` (auto-matched by controller name)
- Pagination: `PaginationConcern` with pagy
- Serializers: ActiveModelSerializers
- Real-time: ActionCable `SessionListChannel` + Inertia `broadcast_refresh_to`

## Other Architecture Docs

- [Container Runtime & Service](./container-runtime.md) — pluggable Docker/K8s runtime + ContainerService refactoring (historical)
- [Workflow Engine](./workflows.md) — workflow data models and execution flow
