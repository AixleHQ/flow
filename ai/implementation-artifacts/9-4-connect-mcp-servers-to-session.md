# Story 9.4: Connect MCP Servers to Session

Status: review

## Story

As a system,
I want to connect configured MCP servers to the agent session based on `session.session_config["mcp_server_ids"]`,
so that the agent can access tools (internal and external) via the MCP protocol.

## Acceptance Criteria

1. **MCP servers from `session.session_config["mcp_server_ids"]`** loaded and configured
2. **Merge with internal MCP**: session already has `MCP_SERVER_URL` + `MCP_SESSION_KEY` for internal Aixle MCP — external servers added on top
3. **Per-CLI MCP config format**: each CLI expects MCP config in different format/location:
   - Claude Code: `.mcp.json` in project root or `~/.claude.json` (mcpServers key)
   - Codex: `~/.codex/config.toml` under `[mcp_servers]` section
   - Gemini CLI: `~/.gemini/settings.json` under `mcpServers` key
   - Cursor CLI: `.cursor/mcp.json`
4. **MCP config file generated and injected** into container at correct path per CLI type
5. **Server connection details**: URL, transport type, headers (from MCPServer model) included in config
6. **Secret resolution in headers**: MCP server headers may reference ConfigItem secrets (same `config_item:NAME` syntax from Story 9.3)
7. **Internal MCP always included**: Aixle's internal MCP server always present regardless of session_config
8. **Disabled/missing servers excluded**: only enabled, existing MCPServer records included; invalid IDs skipped with warning

## Tasks / Subtasks

- [x] Task 1: Add MCP config generation to SessionContextService (AC: #1, #3-5)
  - [x] `SessionContextService.generate_mcp_config(session)` → returns `{ path => content }` hash
  - [x] Per-CLI format generators:
    - [x] `build_claude_mcp(servers)` → JSON for `/workspace/.mcp.json`
    - [x] `build_codex_mcp_toml(servers)` → TOML for `config.toml` append
    - [x] `build_gemini_mcp_json(servers)` → JSON for `settings.json` mcpServers merge
    - [x] `build_cursor_mcp(servers)` → JSON for `/workspace/.cursor/mcp.json`
  - [x] Each generator takes resolved MCPServer data and produces CLI-native format

- [x] Task 2: Resolve MCP server list for session (AC: #1, #7, #8)
  - [x] `resolve_mcp_servers(session)` — private method
  - [x] Read `session.mcp_server_ids` (renamed accessor from Story 9.1)
  - [x] Load `MCPServer.where(id: ids, enabled: true)` — only enabled, skip missing
  - [x] Internal MCP via env vars (already handled in build_env_vars)
  - [x] Log warnings for invalid/missing IDs

- [x] Task 3: Resolve secrets in MCP headers (AC: #6)
  - [x] `resolve_embedded_references` handles embedded `config_item:NAME` patterns via gsub
  - [x] Example: `"Bearer config_item:TAVILY_API_KEY"` → `"Bearer tvly-secret"`

- [x] Task 4: Integrate into AgentSessionStrategy.before_exec (AC: #2)
  - [x] Step 3 in before_exec: `SessionContextService.inject_mcp_config(container_id, session)`
  - [x] Gemini: merges mcpServers into existing settings.json
  - [x] Codex: appends MCP section to existing config.toml
  - [x] Claude/Cursor: writes fresh MCP config files

- [x] Task 5: Write tests (AC: #1-8)
  - [x] Test MCP config generation for all 4 CLI formats
  - [x] Test server resolution (enabled only, skip disabled/missing)
  - [x] Test secret resolution in headers (embedded config_item refs)
  - [x] Test internal MCP via env vars (covered by existing strategy tests)
  - [x] Test merge with existing Gemini settings
  - [x] Test append to existing Codex config.toml
  - [x] Test empty mcp_server_ids (skip gracefully)

## Dev Notes

### Architecture Patterns

- **MCP config is a FILE, not env vars**: External MCP servers are configured via files injected during `before_exec`. Internal MCP uses env vars (`MCP_SERVER_URL`, `MCP_SESSION_KEY`) set at container creation.
- **Format per CLI**: Critical — each CLI reads MCP config from different paths and formats.
- **Merge, not overwrite**: If config file already exists from Story 9.2 injection, read it first, add mcpServers section, write back.

### MCP Config Formats (from CLI Research)

**Claude Code** (`/workspace/.mcp.json`):
```json
{
  "mcpServers": {
    "server-name": {
      "command": "npx",
      "args": ["-y", "@tavily/mcp-server"],
      "env": { "TAVILY_API_KEY": "..." }
    }
  }
}
```

**Codex** (`~/.codex/config.toml` append):
```toml
[mcp_servers.server-name]
type = "http"
url = "https://api.example.com/mcp"
headers = { Authorization = "Bearer ..." }
```

**Gemini CLI** (`~/.gemini/settings.json` merge):
```json
{
  "mcpServers": {
    "server-name": {
      "command": "...",
      "args": ["..."],
      "env": { "API_KEY": "..." },
      "trust": true
    }
  }
}
```

**Cursor CLI** (`/workspace/.cursor/mcp.json`):
```json
{
  "mcpServers": {
    "server-name": {
      "url": "https://api.example.com/mcp",
      "headers": { "Authorization": "Bearer ..." }
    }
  }
}
```

### MCP Config File Paths per CLI

| CLI | MCP Config Path | Format |
|-----|----------------|--------|
| Claude Code | `/workspace/.mcp.json` | JSON |
| Codex | `~/.codex/config.toml` (append) | TOML |
| Gemini CLI | `~/.gemini/settings.json` (merge) | JSON |
| Cursor CLI | `/workspace/.cursor/mcp.json` | JSON |

### Execution Order in before_exec (after all 9.x stories)

```ruby
def before_exec(context)
  container_id = context[:container].id[0..11]
  session = TerminalSession.find(input[:session_id])

  # 1. Credentials (existing)
  input[:credential]&.write_to_container(container_id)

  # 2. Config files (Story 9.2)
  SessionContextService.inject_config_files(container_id, session)

  # 3. MCP config (Story 9.4) — after config files to enable merge
  SessionContextService.inject_mcp_config(container_id, session)
end
```

### Key Code References

- **MCPServer model**: `web/app/models/mcp_server.rb` — `merged_for_project`, transport, url, headers
- **AgentSessionStrategy.build_env_vars**: Already sets `MCP_SERVER_URL`, `MCP_SESSION_KEY`
- **AgentSessionStrategy.before_exec**: Where file injection happens
- **ConfigItem resolution**: Reuse from Story 9.3

### Project Structure Notes

- Modified: `web/app/services/session_context_service.rb` — add MCP config generation
- Modified: `web/app/services/container_strategies/agent_session_strategy.rb` — add MCP injection
- Tests: `web/test/services/session_context_service_test.rb` — add MCP tests

### References

- [Source: web/app/models/mcp_server.rb — MCPServer model]
- [Source: web/app/services/container_strategies/agent_session_strategy.rb — env vars + before_exec]
- [Source: ai/cli_agents_deep_research.md — per-CLI MCP config formats]

## Dev Agent Record

### Agent Model Used
Claude claude-4.6-opus (Cursor Agent)

### Debug Log References
- Secret resolution in headers: initial `start_with?("config_item:")` approach failed for embedded refs like `"Bearer config_item:KEY"`. Fixed with `resolve_embedded_references` using gsub pattern.

### Completion Notes List
- Added `generate_mcp_config`, `inject_mcp_config` to SessionContextService
- 4 per-CLI format builders: Claude JSON, Cursor JSON, Gemini JSON merge, Codex TOML append
- `resolve_mcp_servers` filters by enabled + logs missing
- `resolve_embedded_references` handles `config_item:NAME` anywhere in header values
- Gemini: reads existing settings.json, deep merges mcpServers, writes back
- Codex: reads existing config.toml, appends MCP sections
- Integrated as step 3 in `AgentSessionStrategy.before_exec`
- 12 tests for MCP config generation, injection, server resolution, secret resolution

### File List
- `web/app/services/session_context_service.rb` (modified)
- `web/app/services/container_strategies/agent_session_strategy.rb` (modified)
- `web/test/services/session_context_service_test.rb` (modified)

### Change Log
- 2026-02-06: Story 9-4 implemented — per-CLI MCP config generation + injection with secret resolution and merge support
