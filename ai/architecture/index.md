# Architecture Decision Document

**Updated:** 2026-02-21

## Table of Contents

- [Core Architectural Decisions](./core-architectural-decisions.md)
  - [Data Architecture](./core-architectural-decisions.md#data-architecture)
  - [Authentication & Security](./core-architectural-decisions.md#authentication-security)
  - [API & Communication Patterns](./core-architectural-decisions.md#api-communication-patterns)
  - [Frontend Architecture](./core-architectural-decisions.md#frontend-architecture)
  - [Infrastructure & Deployment](./core-architectural-decisions.md#infrastructure-deployment)
- [Implementation Patterns & Consistency Rules](./implementation-patterns-consistency-rules.md)

## Container Execution Architecture

Core pattern: **PhaseActivity → ContainerService → Strategy → Runtime**

### Strategies (what to do)

| Strategy | Inherits | Purpose |
|----------|----------|---------|
| `BaseStrategy` | — | Abstract base: phase hooks, container lifecycle |
| `AgentBaseStrategy` | BaseStrategy | Shared agent logic: image resolution, env vars, ttyd, ports |
| `AgentAuthStrategy` | AgentBaseStrategy | OAuth credential collection via file watching |
| `AgentSessionStrategy` | AgentBaseStrategy | Interactive/non-interactive sessions, log/usage collection |
| `ToolExecutionStrategy` | BaseStrategy | Custom tool execution: command, wait for exit, timeout |

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

Polymorphic `scope` (Company or Project): Agent, Tool, MCPServer, Skill, Asset, ConfigItem, Repository.

Merge pattern: `Model.merged_for_project(project)` → internal + company + project, project overrides company by name.

## Data Model Highlights

- **TerminalSession** — AASM state machine, links to User + Project + Agent + Container, stores token usage
- **AgentCredential** — encrypted config per user/agent, `config_data=` setter encrypts, `config_data` getter decrypts
- **Tool** — custom Docker-based tools, scoped, with ToolFiles and parameters
- **SessionLog** — Shrine-attached log files per session
- **UsageStatistic** — per-session token breakdown and cost

## API Architecture

- Controller patterns and authorization are documented in [Implementation Patterns](./implementation-patterns-consistency-rules.md#api-controller-patterns)
- Controller hierarchy: `ApplicationController` → `Api::V1::ApplicationController` → `Api::V1::Company::ApplicationController`
- Authorization: Pundit policies + `AuthorizationConcern` (auto-matched by controller name)
- Pagination: `PaginationConcern` with pagy
- Serializers: ActiveModelSerializers
- Real-time: ActionCable `TerminalSessionChannel`

## Other Architecture Docs

- [Container Runtime: K8s Pods (Epic 14)](./container-runtime-k8s-pods.md)
- [Container Service Refactoring v2](./container-service-refactoring-v2.md)
- [Workflow System](./workflow-system.md)
