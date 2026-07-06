# Aixle Project Overview

**Updated**: 2026-02-21

---

## Executive Summary

**Aixle** — a SaaS platform for launching AI coding agents (Claude Code, Cursor CLI, Codex, Gemini CLI) in isolated containers with full lifecycle orchestration via Temporal.

### Key capabilities

- **Agent Sessions** — interactive and non-interactive sessions with AI agents in Docker/Kubernetes containers
- **Agent Auth** — automatic onboarding of OAuth credentials for each agent type
- **Tool Execution** — running custom tools in Docker containers with parameters and files
- **Multi-Runtime** — pluggable Docker and Kubernetes runtimes (via the Strategy + Runtime pattern)
- **Usage Tracking** — collecting usage metrics via OTLP and MITM logs for billing
- **Session Context** — injection of configuration, MCP servers, skills, repositories, and assets into containers
- **Asset Management** — uploading, versioning, and reviewing artifacts
- **Multi-tenancy** — Company → Projects with polymorphic scoping for all resources

---

## Tech Stack

| Category | Technology | Version |
|----------|------------|---------|
| **Backend** | Ruby on Rails | 8.1.3 |
| **Ruby** | Ruby | 4.0.5 |
| **Frontend** | React + TypeScript | 19.2 / 5.9 |
| **Database** | PostgreSQL | 15.3 |
| **Cache** | Redis | 7.2 |
| **Orchestration** | Temporal | 1.29.0 |
| **Container (Docker)** | docker-api gem | 2.3 |
| **Container (K8s)** | kubeclient gem | 4.13 |
| **File Storage** | Shrine + S3 | 3.8 |
| **Build** | Vite | 8.1.2 |
| **UI** | Mantine | 9.4 |
| **MCP** | mcp gem | 0.22.0 |
| **Auth** | OmniAuth (Google) + Pundit | — |

---

## Architecture Overview

### Container Execution Framework

A unified architecture for all types of container tasks:

```
PhaseActivity → ContainerService → Strategy → Runtime
```

**Strategies** (define WHAT to do):
- `AgentAuthStrategy` — OAuth onboarding of agents (auth file watching)
- `AgentSessionStrategy` — interactive/non-interactive sessions (credential injection, log collection, usage tracking)
- `ToolStrategy` — running tools (command + parameters, wait for exit), with subclasses `CustomToolStrategy` (Docker custom tools) and `InternalToolStrategy` (in-process platform tools)
- `WorkflowStepStrategy` — agent sessions bound to a workflow step (subclass of `AgentSessionStrategy`)

**Runtimes** (define WHERE to run):
- `DockerRuntime` — local Docker (docker-api gem)
- `KubernetesRuntime` — Kubernetes Pods + Services + Traefik IngressRoutes (kubeclient + websocket)

**Phases** (container lifecycle):
```
pull_image → create_container → start_container → exec → cleanup
```

Each phase has `before_*` and `after_*` hooks (for example, `before_create_container` for injecting env vars).

### Agent Adapters

Adapters for each type of AI agent:

| Agent | Adapter | Auth Config Path | Usage Tracking |
|-------|---------|-----------------|----------------|
| Claude Code | `ClaudeCodeAdapter` | `~/.claude.json` | OTLP |
| Cursor CLI | `CursorCliAdapter` | `~/.config/cursor/auth.json` | MITM logs + API |
| Codex | `CodexAdapter` | `~/.codex/auth.json` | MITM logs |
| Gemini CLI | `GeminiCliAdapter` | `~/.gemini/oauth_creds.json` | OTLP |

Adapters implement: `config_path`, `generate_config`, `extract_credentials`, `collect_usage`, `session_command`, `skill_files`, `mcp_config`.

### Temporal Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ContainerWorkflow` | API request | Container lifecycle orchestration (auth/session/tool) |
| `StaleSessionCleanupWorkflow` | Hourly cron | Cleanup stuck sessions |
| `DismissedAssetCleanupWorkflow` | Daily cron | Remove dismissed assets after 7-day grace period |

(Plus additional workflows: `CoderSweepExpiredLocksWorkflow`, `OutboxRelayWorkflow`, `QuotaErrorScanWorkflow`, `ScheduledTriggerWorkflow`, `WorkflowExecutionWorkflow`.)

### Multi-tenancy & Scoping

Polymorphic `scope` (Company/Project) for: Agent, Tool, MCPServer, Skill, Asset, ConfigItem, Repository.

Merge logic: `visible_for_project` unions code/platform + company-scoped + project-scoped rows (System-scoped and non-attachable meta/Builder rows excluded via `user_attachable`); no name-level override.

---

## Data Model (Key Entities)

### Core
- **Company** — tenant (users, projects, scoped resources)
- **User** — state machine (active/pending/suspended), onboarding flow, role (employee/admin/super_admin)
- **Project** — company → project hierarchy, collaborators

### Agent Infrastructure
- **TerminalSession** — state machine (not_started → running → ready → finished/failed), links user + project + agent + container
- **AgentCredential** — encrypted agent OAuth credentials per user/agent_type
- **SessionLog** — collected log files (terminal output, MITM HTTP logs) per session
- **UsageStatistic** — token usage & cost breakdown per session

### Tools & Configuration
- **Tool** — custom Docker-based tools with command, parameters, scoped to company/project
- **ToolFile** — files mounted into tool containers
- **Agent** — configured agent personas with system prompts
- **MCPServer** — MCP server connections (HTTP/SSE)
- **Skill** — injectable skill files for agents
- **ConfigItem** — secrets & variables (encrypted), scoped to company/project

### Assets
- **Asset** — versioned files with soft delete, review workflow
- **AssetVersion** — Shrine-attached file versions

### Integrations
- **Integration** — GitHub/Linear connections per company
- **Repository** — linked Git repositories

---

## API Structure

```
/api/v1/
  sessions                          # Auth (login/logout/oauth)
  current_user                      # Profile
  terminal_sessions                 # Create/manage sessions
  assets/presign, assets/upload     # Direct upload
  internal/ws_auth                  # WebSocket auth
  internal/usage_statistics         # OTLP usage ingestion

  company/
    users, agents, tools, mcp_servers, skills
    repositories (available, branches)
    assets (download, versions, restore)
    terminal_sessions (read-only)
    config_items, integrations
    projects/
      collaborators, config_items, agents, tools
      mcp_servers, skills, repositories, assets
      terminal_sessions

/admin/                             # Administrate panel
/cable                              # ActionCable WebSocket
/action_mcp                         # MCP server engine
```

---

## Quick Start

```bash
make setup   # First time: build, install deps, prepare database
make up      # Daily: start all services
make test    # Run test suite

# Access
open http://localhost:4000      # Web UI
open http://localhost:8080      # Temporal UI
```

---

## Team

| Role | Owner |
|------|-------|
| Backend, Architecture, UI | Artem |
