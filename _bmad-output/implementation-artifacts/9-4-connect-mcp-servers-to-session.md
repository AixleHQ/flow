# Story 9.4: Connect MCP Servers to Session

Status: ready-for-dev

## Story

As a system,
I want to connect configured MCP servers to the agent session based on `session.session_config["mcp_server_ids"]`,
so that the agent can access tools (internal and external) via the MCP protocol.

## Acceptance Criteria

1. **MCP servers from `session.session_config["mcp_server_ids"]`** loaded and configured
2. **Merge with internal MCP**: session already has `MCP_SERVER_URL` + `MCP_SESSION_KEY` for internal Palad MCP — external servers added on top
3. **Per-CLI MCP config format**: each CLI expects MCP config in different format/location:
   - Claude Code: `.mcp.json` in project root or `~/.claude.json` (mcpServers key)
   - Codex: `~/.codex/config.toml` under `[mcp_servers]` section
   - Gemini CLI: `~/.gemini/settings.json` under `mcpServers` key
   - Cursor CLI: `.cursor/mcp.json`
4. **MCP config file generated and injected** into container at correct path per CLI type
5. **Server connection details**: URL, transport type, headers (from MCPServer model) included in config
6. **Secret resolution in headers**: MCP server headers may reference ConfigItem secrets (same `config_item:NAME` syntax from Story 9.3)
7. **Internal MCP always included**: Palad's internal MCP server always present regardless of session_config
8. **Disabled/missing servers excluded**: only enabled, existing MCPServer records included; invalid IDs skipped with warning

## Tasks / Subtasks

- [ ] Task 1: Add MCP config generation to SessionContextService (AC: #1, #3-5)
  - [ ] `SessionContextService.generate_mcp_config(session)` → returns `{ path => content }` hash
  - [ ] Per-CLI format generators:
    - [ ] `generate_claude_mcp_config(servers)` → JSON for `.mcp.json`
    - [ ] `generate_codex_mcp_config(servers)` → TOML for `config.toml` append
    - [ ] `generate_gemini_mcp_config(servers)` → JSON for `settings.json` mcpServers
    - [ ] `generate_cursor_mcp_config(servers)` → JSON for `.cursor/mcp.json`
  - [ ] Each generator takes `MCPServer` instances and produces CLI-native format

- [ ] Task 2: Resolve MCP server list for session (AC: #1, #7, #8)
  - [ ] `SessionContextService.resolve_mcp_servers(session)`
  - [ ] Read `session.session_mcp_server_ids` (helper from Story 9.1)
  - [ ] Load `MCPServer.where(id: ids, enabled: true)` — only enabled, skip missing
  - [ ] Always include internal MCP servers via env vars (already handled)
  - [ ] Log warnings for invalid/missing IDs

- [ ] Task 3: Resolve secrets in MCP headers (AC: #6)
  - [ ] MCP server `headers` jsonb may contain `config_item:API_KEY` references
  - [ ] Reuse `SessionContextService.resolve_config_item_reference` from Story 9.3
  - [ ] Example: `{ "Authorization": "Bearer config_item:TAVILY_API_KEY" }` → resolved

- [ ] Task 4: Integrate into AgentSessionStrategy.before_exec (AC: #2)
  - [ ] After config files injection (Story 9.2): generate MCP config and inject
  - [ ] Call `SessionContextService.generate_mcp_config(session)`
  - [ ] Write generated config files to container (same write pattern as 9.2)
  - [ ] Merge with existing config files if they already exist (don't overwrite)

- [ ] Task 5: Write tests (AC: #1-8)
  - [ ] Test MCP config generation for each CLI format
  - [ ] Test server resolution (enabled only, skip missing)
  - [ ] Test secret resolution in headers
  - [ ] Test internal MCP always present via env vars
  - [ ] Test merge with existing config files
  - [ ] Test empty mcp_server_ids (skip gracefully)

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

### Debug Log References

### Completion Notes List

### File List
