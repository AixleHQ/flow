# Epic 8: Session Context (Phase 4)

Admins can configure per-CLI session context with credentials and MCP.

**FRs covered:** FR53, FR54, FR55, FR56

**Phase:** 4 (Depends on: Epic 7 MCP Servers)

**User Outcome:** Sessions start with correct configuration for each CLI type.

## Story 8.1: Configure Session Context per CLI Type

As a company admin,
I want to configure session context per CLI type,
So that each agent type has correct configuration.

**Acceptance Criteria:**
- Can configure context for: Claude Code, Cursor CLI, Codex, Gemini CLI
- Context includes: config_files, env_vars, mcp_servers
- Context scoped to company

## Story 8.2: Inject Config Files into Container

As a system,
I want to inject config files into container based on CLI type,
So that agent CLI is properly configured.

**Acceptance Criteria:**
- Config files written to correct paths (e.g., ~/.claude/settings.json)
- Content from SessionContextConfig.config_files
- Files created before session starts

## Story 8.3: Inject Environment Variables with Secrets

As a system,
I want to inject environment variables with resolved secrets,
So that agent has required credentials.

**Acceptance Criteria:**
- Env vars from SessionContextConfig.env_vars
- Secret references resolved (e.g., "secret:api_key" → actual value)
- Vars set in container environment

## Story 8.4: Connect MCP Servers to Session

As a system,
I want to connect configured MCP servers to session,
So that agent can access tools via MCP.

**Acceptance Criteria:**
- MCP servers from SessionContextConfig.mcp_servers started
- Connection established before agent starts
- MCP server URL/config provided to agent

---
