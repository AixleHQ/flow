# Architecture Decision Document

## Table of Contents

- [Core Architectural Decisions](./core-decisions.md)
  - [Data Architecture](./core-decisions.md#data-architecture)
  - [Authentication & Authorization](./core-decisions.md#authentication--authorization)
  - [API Design](./core-decisions.md#api-design)
  - [Frontend Architecture](./core-decisions.md#frontend-architecture)
  - [Infrastructure](./core-decisions.md#infrastructure)
- [Implementation Patterns & Consistency Rules](./implementation-patterns.md)

## Container Execution Architecture

Core pattern: **PhaseActivity → ContainerService → Strategy → Runtime**

### Strategies (what to do)

| Strategy | Inherits | Purpose |
|----------|----------|---------|
| `BaseStrategy` | — | Abstract base: phase hooks, container lifecycle |
| `AgentBaseStrategy` | BaseStrategy | Shared agent logic: image resolution, env vars, ttyd, ports |
| `AgentAuthStrategy` | AgentBaseStrategy | Credential capture via file watching while the user completes the CLI's login |
| `AgentSessionStrategy` | AgentBaseStrategy | Interactive/non-interactive sessions, log/usage collection |
| `WorkflowStepStrategy` | AgentSessionStrategy | Agent session bound to a workflow step |
| `ToolStrategy` | BaseStrategy | Base for tool execution: command, wait for exit, timeout |
| `CustomToolStrategy` | ToolStrategy | User-defined Docker-based custom tool execution |
| `InternalToolStrategy` | ToolStrategy | Platform-provided (code-source) tool execution |

### Runtimes (where to run)

| Runtime | Backend | Used for |
|---------|---------|----------|
| `DockerRuntime` | docker-api gem; `Docker::Container` | Local development (the default) |
| `KubernetesRuntime` | kubeclient + websocket; Pods + Services + IngressRoutes | Production |

Runtime selected via `Settings.container_runtime` (`CONTAINER_RUNTIME`: `kubernetes` or `k8s` selects Kubernetes, anything else Docker).

Both runtimes' `exec` return `[stdout, stderr, exit_code]`, with stdout and stderr as arrays of strings (Kubernetes splits its output into lines; Docker returns the daemon's chunks). `exec!` is the variant for callers that must tell "the container is gone" from "the command failed": on Kubernetes it raises `ContainerRuntime::ContainerUnreachableError` when the pod cannot be reached, instead of reporting exit code 1; Docker, which cannot tell the two apart, answers as `exec` does.

### Agent Adapters

One adapter per runtime in `app/services/agents/`, registered in `AgentCredentialsService::ADAPTERS`. Each declares its home directory and auth files (`home_dir`, `config_path`, `auth_watch_path`), renders the CLI's config, and records usage:

| Adapter | Runtime | Usage comes from |
|---------|---------|------------------|
| `ClaudeCodeAdapter` | `claude_code` | OTLP telemetry, streamed during the session |
| `CursorCliAdapter` | `cursor_cli` | Cursor's usage API, matched to request windows from the MITM log at cleanup |
| `CodexAdapter` | `codex` | OTLP logs, streamed; the MITM log at cleanup as a fallback |
| `GeminiCliAdapter` | `gemini_cli` | OTLP telemetry, streamed |
| `AntigravityCliAdapter` | `antigravity_cli` | The CLI's stream-json `result` event, at cleanup |
| `GrokAdapter` | `grok` | The MITM log, at cleanup |
| `KiroCliAdapter` | `kiro_cli` | OTLP credit telemetry, streamed; MITM-captured usage summaries, then the account's credit counter, as fallbacks |

### Container Lifecycle Phases

```
pull_image → create_container → start_container → exec → cleanup
```

Each phase calls: `before_X(**state)` → `X(**state)` → `after_X(**state)`

ContainerService merges returned hashes into shared state between phases.

## Temporal Workflows

| Workflow | Started by | Does |
|----------|------------|------|
| `ContainerWorkflow` (`ContainerWorkflowV2` for sessions admitted through the queue) | A session, auth, or tool launch | The full container lifecycle, with signal support for interactive sessions |
| `WorkflowExecutionWorkflow` (`…V2` when step sessions are queued) | A workflow run | Walks the run's steps and waits for each step's session |
| `ScheduledTriggerWorkflow` | A Temporal Schedule per schedule trigger | Fires the trigger binding |
| Sweeps and syncs | `app/temporal/schedules.yml` | Stale sessions and runs, orphaned resources, token refresh, catalog syncs, and the other periodic jobs listed there |

### Error Handling

- [Temporal Error Handling](./temporal-error-handling.md) — retryable vs non-retryable, benign exceptions
- `TemporalExceptions.wrap(error, retryable:, benign:)` — wraps into `Temporalio::Error::ApplicationError`
- `PhaseError` (from ContainerService) → non-retryable
- `Docker::Error::DockerError` → retryable

## Multi-tenancy

Users belong to companies through `CompanyMembership` (a user can hold several). Polymorphic `scope` (Company or Project): Agent, Tool, Workflow, MCPServer, Skill, Asset, ConfigItem, Repository.

Visibility scopes: `Model.visible_for_project(project)` and `Model.visible_for_company(company)` (plus `for_project`/`for_company` for a single scope). `visible_for_project` is a union of Company-scoped and Project-scoped rows (System-scoped rows excluded); `visible_for_company` returns Company-scoped rows. No name-based override between scopes.

## Data Model Highlights

- **TerminalSession** — AASM state machine, links to User + Project + `configured_agent` (Agent), stores token usage
- **AgentCredential** — encrypted config per user, company, and agent type; `config_data=` setter encrypts, `config_data` getter decrypts
- **Tool** — custom Docker-based tools, scoped, with ToolFiles and parameters
- **SessionLog** — Shrine-attached log files per session
- **UsageStatistic** — per-session token breakdown and cost

## API Architecture

- Controller patterns and authorization are documented in [Implementation Patterns](./implementation-patterns.md#api-controller-patterns)
- Controller hierarchy: `ApplicationController` → `Api::V1::ApplicationController` (declares `dynamic_authorize!`). Company controllers (e.g. `Api::V1::Company::AssetsController`) inherit directly from `Api::V1::ApplicationController` and use AuthConcern's `current_company`; `current_project` lives in `Api::V1::Projects::ApplicationController`.
- Authorization: Pundit policies + `AuthorizationConcern` (auto-matched by controller name)
- Pagination: `PaginationConcern` with pagy
- Serialization: Alba resources in `app/resources/` (`ApplicationResource`); Typelizer generates the TypeScript types in `app/frontend/types/generated/`
- Real-time: Inertia Cable signed streams (refresh signals and id-only row updates; no custom channels — see core-decisions.md)

## Other Architecture Docs

- [Container Runtime & Service](./container-runtime.md) — pluggable Docker/K8s runtime + ContainerService refactoring (historical)
- [Workflow Engine](./workflows.md) — workflow data models and execution flow
