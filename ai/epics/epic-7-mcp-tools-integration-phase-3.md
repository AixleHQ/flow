# Epic 7: MCP Tools Integration (Phase 3)

Agents can discover and execute custom tools via MCP protocol.

**FRs covered:** FR49, FR50, FR51, FR52

**Phase:** 3 (Depends on: Epic 6 Tools)

**User Outcome:** CLI agents can use custom tools through MCP protocol.

## Architecture Decision

**Approach:** Single MCP server embedded in Rails app using ActionMCP gem with dynamic tool resolution via monkey-patch.

**Why not separate MCP containers?**
- Simpler deployment (no sidecar management)
- Proven pattern (used in other projects)
- Session-based tool filtering built into Rails

```
Agent ──MCP(SSE)──→ Rails/ActionMCP ──Temporal──→ ToolExecutionWorkflow
         ↑                 ↑
    X-Session-Key    Gateway auth +
                     dynamic tools/list
```

## Story 7.1: Dynamic MCP Tools Integration

As a system,
I want to expose custom tools to agents via MCP protocol using ActionMCP,
So that agents can discover and execute tools based on their session context.

**Acceptance Criteria:**
- ActionMCP gem installed and configured
- Gateway authenticates by `mcp_key` header
- `tools/list` returns only tools available for current session
- `tools/call` executes tool via `ToolExecutionWorkflow` (Temporal)
- Session has `mcp_key` for MCP authentication
- Session has `available_tools` association (many-to-many)
- Agent container receives MCP config with session key at startup

## Story 7.2: Select Tools for Session (UI)

As a user,
I want to select which custom tools are available when starting a standalone session,
So that I control what capabilities the agent has.

**Acceptance Criteria:**
- Session start form shows available custom tools (company + project merged)
- Can select 0..N tools for the session
- Selected tools saved to `session_tools` join table
- Default: no tools selected (explicit opt-in)

## Story 7.3: Tool Selection for Workflow Steps (deferred)

As a workflow designer,
I want to specify which tools are available for each workflow step,
So that agents have appropriate capabilities per step.

**Status:** Deferred to Epic 11 (Workflows)

**Note:** Will reuse `session_tools` pattern but configured per workflow step.

## Story 7.4: MCP Server Management

As a company/project admin,
I want to configure MCP servers (internal and custom),
So that agents can access additional tools from external providers like Context7, Tavily, etc.

**MCP Server Types:**
| Type | Description | Scope |
|------|-------------|-------|
| `internal` | System-provided (Palad tools MCP) | Global (automatic) |
| `custom` | User-configured external servers | Company or Project |

**Acceptance Criteria:**
- MCP Server model with `kind`: internal | custom
- Can create custom MCP server with: name, url, transport (sse/stdio), headers (JSON), description
- Custom servers scoped to company or project (polymorphic)
- Internal server is auto-configured per session (from 7.1)
- Can enable/disable MCP servers
- Can edit and delete custom servers only
- UI for managing MCP servers (company-level and project-level)
- Session can have multiple MCP servers (internal + selected custom)

## Story 7.5: Select MCP Servers for Session

As a user,
I want to select which MCP servers are available when starting a session,
So that I control what external tools the agent can access.

**Acceptance Criteria:**
- Session start form shows available MCP servers (company + project merged)
- Internal "Palad Tools" always included if custom tools selected
- Can select 0..N custom MCP servers
- Selected servers saved to `session_mcp_servers` join table
- MCP config injected into agent container with all selected servers

---
