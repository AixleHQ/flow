# Story 9.1: Add session_config to TerminalSession

Status: review

## Story

As a user starting an agent session,
I want to pass session configuration (config files, env vars, MCP server IDs, agent ID) when creating a session,
so that the system knows what to inject into the container.

## Acceptance Criteria

1. **New JSONB field** `session_config` on `TerminalSession` with default `{}`
2. **API accepts** `session_config` in `POST /api/v1/.../terminal_sessions` create params
3. **Serializer includes** `session_config` in API responses
4. **Helper accessors** on model: `session_config_files`, `session_env_vars`, `session_mcp_server_ids`, `session_agent_id`
5. **Validation**: `session_config` must be a Hash (not string/array), keys limited to known set (`config_files`, `env_vars`, `mcp_server_ids`, `agent_id`)
6. **Auth setup sessions** work with empty `session_config` (backwards compatible)
7. **Agent sessions** can receive full `session_config` with all keys populated

## Tasks / Subtasks

- [x] Task 1: Migration (AC: #1)
  - [x] `add_column :terminal_sessions, :session_config, :jsonb, default: {}, null: false`

- [x] Task 2: Model helpers and validation (AC: #4, #5, #6)
  - [x] Accessor helpers reading from session_config hash:
    - `session_config_files` → `session_config["config_files"] || {}`
    - `session_env_vars` → `session_config["env_vars"] || {}`
    - `session_mcp_server_ids` → `session_config["mcp_server_ids"] || []`
    - `session_tool_ids` → `session_config["tool_ids"] || []`
    - `session_agent_id` → `session_config["agent_id"]`
  - [x] ~~Callback removed~~: `available_tools` now reads `tool_ids` directly from JSONB via `Tool.where(id:)` — no `session_tools` join table needed
  - [x] Validation: `session_config` must be a Hash
  - [x] Validation: only allowed keys (`config_files`, `env_vars`, `mcp_server_ids`, `tool_ids`, `agent_id`)

- [x] Task 3: Update API (AC: #2, #3)
  - [x] Add `session_config` to strong params in terminal_sessions controller
  - [x] Add `session_config` to serializer

- [x] Task 4: Write tests (AC: #1-7)
  - [x] Test creating session with session_config
  - [x] Test helper accessors return correct values
  - [x] Test empty session_config (auth_setup backwards compat)
  - [x] Test validation rejects non-Hash values
  - [x] Test serialization includes session_config

## Dev Notes

### session_config Structure

```json
{
  "config_files": {
    "~/.claude/settings.json": "{ json content }",
    "CLAUDE.md": "# Context markdown"
  },
  "env_vars": {
    "ANTHROPIC_API_KEY": "config_item:ANTHROPIC_API_KEY",
    "NODE_ENV": "production"
  },
  "mcp_server_ids": [1, 5, 12],
  "tool_ids": [3, 7, 14],
  "agent_id": 42
}
```

- `config_files`: path → content mapping, injected into container (Story 9.2)
- `env_vars`: name → value mapping, `config_item:NAME` syntax resolved from ConfigItem (Story 9.3)
- `mcp_server_ids`: external MCPServer IDs to connect via per-CLI config files (Story 9.4)
- `tool_ids`: Tool IDs exposed through internal Palad MCP (`session_tools` join table created from these)
- `agent_id`: Agent persona to load (Story 9.8)

### Config Sources

- **Standalone session**: UI sends full session_config in create API call
- **Workflow step**: WorkflowStep populates session_config when creating TerminalSession
- **Auth setup**: session_config is empty `{}` — only credentials loaded

### Key Code References

- **TerminalSession model**: `web/app/models/terminal_session.rb` — add field + helpers
- **Controller**: `web/app/controllers/api/v1/` — terminal_sessions_controller (find by grep)
- **Serializer**: `web/app/serializers/` — terminal_session_serializer
- **Existing JSONB field**: `metadata` on TerminalSession — similar pattern but for operational data

### Per-CLI Config Paths (from CLI Research)

| CLI | Config Dir | Auth Env Var | Context File | MCP Config |
|-----|-----------|-------------|-------------|------------|
| Claude Code | `~/.claude/` | `ANTHROPIC_API_KEY` | `CLAUDE.md` | `.mcp.json` |
| Codex | `~/.codex/` | `CODEX_API_KEY` | `AGENTS.md` | `config.toml` [mcp] |
| Gemini CLI | `~/.gemini/` | `GEMINI_API_KEY` | `GEMINI.md` | `settings.json` mcpServers |
| Cursor CLI | `~/.cursor/` | `CURSOR_API_KEY` | `.cursorrules` | `mcp.json` |

### Project Structure Notes

- Migration: `web/db/migrate/YYYYMMDDHHMMSS_add_session_config_to_terminal_sessions.rb`
- Model changes: `web/app/models/terminal_session.rb`
- Tests: existing terminal_session controller/model tests

### References

- [Source: ai/workflow-architecture.md#10.4 Session Context]
- [Source: ai/cli_agents_deep_research.md — per-CLI config paths]
- [Source: web/app/models/terminal_session.rb — current model]

## Dev Agent Record

### Agent Model Used
Claude claude-4.6-opus (Cursor Agent)

### Debug Log References
- Strong params: `session_config: {}` syntax doesn't support nested hashes/arrays for JSONB. Fixed by using `permit!.to_h` extraction pattern (same approach safe because model-level validation enforces allowed keys).

### Completion Notes List
- Added `session_config` JSONB column with migration
- Implemented 5 accessor helpers for reading session_config sub-keys
- Rewrote `available_tools` to read `tool_ids` directly from JSONB — eliminated `session_tools` join table dependency
- Added model validation: must be Hash, only allowed keys
- Updated controller strong params with `permit!` for complex JSONB structure
- Added `session_config` to serializer
- 18 model tests + 2 controller tests added, all passing
- Full suite: 695 runs, 0 failures, 0 regressions

### File List
- `web/db/migrate/20260206100001_add_session_config_to_terminal_sessions.rb` (new)
- `web/app/models/terminal_session.rb` (modified)
- `web/app/controllers/api/v1/terminal_sessions_controller.rb` (modified)
- `web/app/serializers/api/v1/terminal_session_serializer.rb` (modified)
- `web/test/models/terminal_session_test.rb` (new)
- `web/test/factories/terminal_sessions.rb` (modified)
- `web/test/controllers/api/v1/terminal_sessions_controller_test.rb` (modified)
- `web/db/schema.rb` (auto-updated by migration)

### Change Log
- 2026-02-06: Story 9-1 implemented — session_config JSONB field with helpers, validation, API support, and tests
