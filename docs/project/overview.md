# Aixle Project Overview

---

## Executive Summary

**Aixle Flow** — a platform for running AI coding agents (Claude Code, Cursor CLI, Codex, Gemini CLI, Antigravity CLI, Grok, Kiro CLI) in isolated containers, driven from a team board, with full lifecycle orchestration via Temporal.

### Key capabilities

- **Board + workflows** — column → workflow bindings; a workflow is a DAG of agent steps with retries, approval gates, and parallel runs
- **Agent Sessions** — interactive and non-interactive sessions with AI agents in containers (Docker locally, Kubernetes in production)
- **Agent Auth** — each user signs in to each runtime's own CLI once, in a terminal in the browser; the credential is captured and stored encrypted
- **Tool Execution** — custom tools in containers with parameters and files, platform tools in-process, MCP servers
- **Multi-Runtime** — pluggable Docker and Kubernetes runtimes (via the Strategy + Runtime pattern)
- **Usage Tracking** — tokens and cost per session, from OTLP telemetry, MITM proxy logs, or the CLI's own output
- **Session Context** — injection of configuration, MCP servers, skills, repositories, and assets into containers
- **Asset Management** — uploading, versioning, and reviewing artifacts
- **Multi-tenancy** — Company → Projects with polymorphic scoping for resources; a user can belong to several companies
- **Personal MCP** — a user can drive their own account from an external agent with a personal MCP token

---

## Tech Stack

| Category | Technology |
|----------|------------|
| **Backend** | Ruby on Rails |
| **Frontend** | React + TypeScript, Inertia.js, Mantine, Vite |
| **Database** | PostgreSQL (also backs Solid Queue jobs) |
| **Cache / Action Cable** | Redis |
| **Orchestration** | Temporal |
| **Containers** | docker-api gem (Docker), kubeclient gem (Kubernetes) |
| **File Storage** | Shrine + S3 |
| **MCP** | `mcp` gem (official Ruby SDK) |
| **Auth** | Email + password, Google OAuth (OmniAuth), invitations; Pundit |
| **Error tracking** | Sentry |

Versions are pinned in `.ruby-version`, `Gemfile.lock`, `package.json` / `yarn.lock`, and `docker-compose.yml`.

---

## Architecture Overview

### Container Execution Framework

A unified architecture for all types of container tasks:

```
PhaseActivity → ContainerService → Strategy → Runtime
```

**Strategies** (define WHAT to do):
- `AgentAuthStrategy` — capturing an agent CLI's login (auth file watching)
- `AgentSessionStrategy` — interactive/non-interactive sessions (credential injection, log collection, usage tracking)
- `ToolStrategy` — running tools (command + parameters, wait for exit), with subclasses `CustomToolStrategy` (Docker custom tools) and `InternalToolStrategy` (in-process platform tools)
- `WorkflowStepStrategy` — agent sessions bound to a workflow step (subclass of `AgentSessionStrategy`)

**Runtimes** (define WHERE to run):
- `DockerRuntime` — local Docker (docker-api gem); the default, used in development
- `KubernetesRuntime` — Kubernetes Pods + Services + Traefik IngressRoutes (kubeclient + websocket); used in production

**Phases** (container lifecycle):
```
pull_image → create_container → start_container → exec → cleanup
```

Each phase has `before_*` and `after_*` hooks (for example, `before_create_container` for injecting env vars).

### Agent Adapters

One adapter per runtime in `app/services/agents/` (`claude_code`, `cursor_cli`, `codex`, `gemini_cli`, `antigravity_cli`, `grok`, `kiro_cli`), on the interface in `app/services/agents/base_adapter.rb`: auth file paths, config generation, credential extraction, session command, MCP config, and usage collection. The per-adapter table (and where each one's usage comes from) is in [architecture/index.md](../architecture/index.md#agent-adapters).

### Temporal Workflows

`ContainerWorkflow` orchestrates a container's lifecycle (auth, session, or tool); `WorkflowExecutionWorkflow` runs a workflow run's steps; `ScheduledTriggerWorkflow` fires schedule triggers. The periodic sweeps and syncs are declared in `app/temporal/schedules.yml`. See [architecture/index.md](../architecture/index.md#temporal-workflows).

### Multi-tenancy & Scoping

Polymorphic `scope` (Company/Project) for: Agent, Tool, Workflow, MCPServer, Skill, Asset, ConfigItem, Repository.

Merge logic: `visible_for_project` unions code/platform + company-scoped + project-scoped rows (System-scoped and non-attachable rows excluded via `user_attachable`); no name-level override.

---

## Data Model (Key Entities)

### Core
- **Company** — tenant (memberships, projects, scoped resources)
- **CompanyMembership** — a user's place in one company: role (`admin` / `employee` / `viewer`), state (invited → active, suspended, revoked), and that company's onboarding
- **User** — account (state machine active/pending/suspended/archived), password and/or Google sign-in, personal MCP token; `super_admin` flag for the platform admin
- **Project** — company → project hierarchy, owner + collaborators

### Agent Infrastructure
- **TerminalSession** — state machine (not_started → running → ready → finishing → finished, waiting in `queued` first when the admission queue holds it; `failed` and `cancelled` from any live state — see `app/state_machines/terminal_session_state_machine.rb`), links user + project + agent + container
- **AgentCredential** — encrypted runtime credentials per user, company, and agent type
- **SessionLog** — collected log files (terminal output, MITM HTTP logs) per session
- **UsageStatistic** — token usage & cost breakdown per session

### Tools & Configuration
- **Tool** — custom Docker-based tools with command, parameters, scoped to company/project
- **ToolFile** — files mounted into tool containers
- **Agent** — configured agent personas with system prompts
- **MCPServer** — MCP server connections (HTTP/SSE/stdio)
- **Skill** — injectable skill files for agents
- **ConfigItem** — secrets & variables (encrypted)

### Assets
- **Asset** — versioned files with soft delete, review workflow
- **AssetVersion** — Shrine-attached file versions

### Integrations
- **Integration** — GitHub, GitLab, Linear, Slack, Coder, and Azure DevOps connections, owned by a company and either company-wide or attached to one project
- **Repository** — linked Git repositories

---

## Surfaces

```
/                     Inertia web app (Rails routes in the Web namespace)
/api/v1/...           JSON API the web app calls (cookie session + CSRF); OpenAPI at /api-docs
/api/v1/internal/...  ws_auth (Traefik ForwardAuth for container terminals), usage_statistics (OTLP ingest)
/mcp, /action_mcp     MCP server (containers are configured with /action_mcp): session keys and personal MCP tokens
/cable                Action Cable (Inertia Cable streams)
/webhooks/...         GitHub, GitLab, Azure DevOps, Slack, and the generic /webhooks/in/:slug
/admin/               Administrate panel (super admins)
/docs                 In-app documentation portal
```

Endpoint-level detail: [reference/api.md](../reference/api.md).

---

## Quick Start

```bash
make setup   # First time: build images, install deps, prepare database
make up      # Daily: start all services
docker compose exec -T web make check_all   # The full check suite, as CI runs it

# Access
open http://localhost:4000      # Web UI
open http://localhost:8080      # Temporal UI
```

---

## Team

| Role | Owner |
|------|-------|
| Backend, Architecture, UI | Artem |
