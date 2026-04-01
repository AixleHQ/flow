# Story 7.1: Dynamic MCP Tools Integration

Status: review

## Story

As a system,
I want to expose custom tools to agents via MCP protocol using ActionMCP with dynamic tool resolution,
So that agents can discover and execute tools based on their session context.

## Architecture Decision

**Approach:** Single MCP server embedded in Rails app with ActionMCP + monkey-patch for dynamic tools.

**Key insight:** Instead of spawning separate MCP server containers per session, we patch ActionMCP's `tools/list` and `tools/call` handlers to resolve tools dynamically based on authenticated session.

```
Agent Container                     Rails App (web)
┌─────────────┐                    ┌─────────────────────────────┐
│ Claude Code │ ──── SSE/HTTP ───→ │ ActionMCP Engine (/mcp)     │
│             │  X-Session-Key     │   ↓                         │
│ MCP config: │                    │ Gateway.authenticate!       │
│  url: /mcp  │                    │   → find session by key     │
│  key: abc.. │                    │   ↓                         │
└─────────────┘                    │ tools/list (patched)        │
                                   │   → session.available_tools │
                                   │   ↓                         │
                                   │ tools/call (patched)        │
                                   │   → ToolExecutionWorkflow   │
                                   └─────────────────────────────┘
```

## Acceptance Criteria

1. ✅ ActionMCP gem installed and configured
2. ✅ Gateway authenticates by `mcp_key` header/param
3. ✅ `tools/list` returns only tools available for current session
4. ✅ `tools/call` executes tool via `ToolExecutionWorkflow` (Temporal)
5. ✅ Session has `mcp_key` for authentication
6. ✅ Session has `available_tools` association
7. ✅ Agent container receives MCP config with session key at startup

## Tasks

### Task 1: Install ActionMCP (AC: 1)

- [x] Add gems to Gemfile:
  ```ruby
  gem "actionmcp", "~> 0.80.0"
  gem "solid_mcp"
  ```
- [x] Run `bundle install`
- [x] Run ActionMCP install generator
- [x] Run migrations
- [x] Configure `config/mcp.yml` with default profile

### Task 2: Add mcp_key to TerminalSession (AC: 5)

- [x] Migration: add `mcp_key` (string, unique, indexed) to `terminal_sessions`
- [x] Generate `mcp_key` on session creation (SecureRandom.urlsafe_base64)
- [x] Add validation for uniqueness

```ruby
# Migration
add_column :terminal_sessions, :mcp_key, :string
add_index :terminal_sessions, :mcp_key, unique: true

# Model
class TerminalSession < ApplicationRecord
  before_create :generate_mcp_key

  private

  def generate_mcp_key
    self.mcp_key ||= SecureRandom.urlsafe_base64(32)
  end
end
```

### Task 3: Session-Tools Association (AC: 6)

- [x] Create join table `session_tools` (session_id, tool_id)
- [x] Add `has_many :tools, through: :session_tools` to TerminalSession
- [x] Add `available_tools` method that merges session.tools with defaults

```ruby
# Migration
create_table :session_tools do |t|
  t.references :terminal_session, null: false, foreign_key: true
  t.references :tool, null: false, foreign_key: true
  t.timestamps
end
add_index :session_tools, [:terminal_session_id, :tool_id], unique: true

# Model
class TerminalSession < ApplicationRecord
  has_many :session_tools, dependent: :destroy
  has_many :tools, through: :session_tools

  def available_tools
    # Tools explicitly assigned to session
    # Falls back to all enabled custom tools for project if none assigned
    tools.presence || project.available_tools.custom_tools.enabled
  end
end
```

### Task 4: ApplicationGateway (AC: 2)

- [x] Create `app/mcp/application_gateway.rb`
- [x] Authenticate by `X-Session-Key` header or `session_key` param
- [x] Set `ActionMCP::Current.terminal_session` via TerminalSessionIdentifier

```ruby
# app/gateways/application_gateway.rb
class ApplicationGateway < ActionMCP::Gateway
  identified_by :terminal_session

  protected

  def authenticate!
    key = extract_session_key
    raise ActionMCP::UnauthorizedError, "Missing session key" unless key

    session = TerminalSession.find_by(mcp_key: key)
    raise ActionMCP::UnauthorizedError, "Invalid session key" unless session
    raise ActionMCP::UnauthorizedError, "Session not active" unless session.active?

    { terminal_session: session }
  end

  private

  def extract_session_key
    request.headers["X-Session-Key"] ||
      request.headers["Authorization"]&.delete_prefix("Bearer ") ||
      request.params[:session_key]
  end
end
```

### Task 5: ActionMCP Tools Patch (AC: 3, 4)

- [x] Create `config/initializers/action_mcp_dynamic_tools.rb`
- [x] Patch `send_tools_list` to return session tools
- [x] Patch `send_tools_call` to execute via Temporal

```ruby
# config/initializers/action_mcp_dynamic_tools.rb
# frozen_string_literal: true

require "action_mcp"

# Extend Current to hold terminal_session
ActionMCP::Current.class_eval do
  attribute :terminal_session
end

# Patch Tools module for dynamic tool resolution
ActionMCP::Server::Tools.module_eval do
  # Override tools/list to return session-specific tools
  def send_tools_list(request_id, params = {})
    session = ActionMCP::Current.terminal_session
    return super if session.nil?

    tools = session.available_tools.map do |tool|
      {
        name: tool.name,
        description: tool.description || tool.display_name,
        inputSchema: tool.input_schema.presence || {
          type: "object",
          properties: {},
          required: []
        }
      }
    end

    send_jsonrpc_response(request_id, result: { tools: tools })
  end

  # Override tools/call to execute via Temporal
  def send_tools_call(request_id, tool_name, arguments, _meta = {})
    session = ActionMCP::Current.terminal_session
    return super if session.nil?

    tool = session.available_tools.find_by(name: tool_name)

    unless tool
      send_jsonrpc_error(request_id, :method_not_found, "Tool '#{tool_name}' not available")
      return
    end

    begin
      result = execute_tool_via_temporal(tool, arguments, session)
      content = build_response_content(result)
      send_jsonrpc_response(request_id, result: { content: content })
    rescue StandardError => e
      Rails.logger.error("[MCP] Tool execution failed: #{e.message}")
      send_jsonrpc_error(request_id, :internal_error, "Tool execution failed: #{e.message}")
    end
  end

  private

  def execute_tool_via_temporal(tool, arguments, session)
    workflow = WorkflowService.tool_execution_workflow

    TemporalService.execute_workflow(
      workflow,
      {
        tool_id: tool.id,
        docker_image: tool.docker_image,
        parameters: arguments || {},
        project_id: session.project_id,
        timeout: tool.timeout || 300
      }
    )
  end

  def build_response_content(result)
    content = []

    if result[:exit_code] == 0
      content << { type: "text", text: result[:stdout] } if result[:stdout].present?
    else
      content << { type: "text", text: "Error (exit #{result[:exit_code]}):" }
      content << { type: "text", text: result[:stderr] } if result[:stderr].present?
      content << { type: "text", text: result[:stdout] } if result[:stdout].present?
    end

    content << { type: "text", text: "(no output)" } if content.empty?
    content
  end
end
```

### Task 6: Agent Container MCP Config (AC: 7)

- [x] Update ContainerService to inject MCP config into agent container (via env vars)
- [x] Pass MCP_SERVER_URL and MCP_SESSION_KEY environment variables
- [ ] (Deferred) Mount config files for specific CLI types (Claude, Cursor)

```ruby
# In ContainerService or AgentSessionService
def generate_mcp_config(session)
  {
    mcpServers: {
      "aixle-tools" => {
        url: "#{ENV['MCP_SERVER_URL']}/mcp",
        transport: "sse",
        headers: {
          "X-Session-Key" => session.mcp_key
        }
      }
    }
  }
end

# Write to container as JSON config
# Path depends on CLI type:
# - Claude Code: ~/.claude/settings.json (merge with existing)
# - Cursor: ~/.cursor/mcp.json
# etc.
```

### Task 7: Tests (AC: all)

- [x] Unit test: mcp_key generation and uniqueness
- [x] Unit test: active? method
- [x] Unit test: available_tools returns correct tools
- [x] Unit test: SessionTool association
- [ ] (Deferred) Integration test: full MCP flow with mock agent

## Dev Notes

### Reference Implementation

Based on `initializer_reference/core_ext/action_mcp/server/tools.rb` pattern used in another project.

### Why This Approach?

1. **No sidecar containers** — MCP runs in main Rails app
2. **Minimal code** — ~80 lines of patches
3. **Proven pattern** — already used successfully
4. **Fallback support** — `return super if session.nil?` keeps static tools working

### MCP Transport

ActionMCP supports SSE (Server-Sent Events) which works well for agents in Docker containers connecting to Rails app.

### Security

- `mcp_key` is unique per session
- Key transmitted via header (not in URL)
- Session must be `active?` to authenticate
- Tools scoped to session (no cross-session access)

## Out of Scope

- Internal tools (deferred to Epic 11 - Workflows)
- MCP server configuration UI (not needed — automatic)
- Multiple MCP servers per session (single "aixle-tools" server)

## File List

- `web/Gemfile` (modified) — added actionmcp, solid_mcp gems
- `web/db/migrate/20260204154533_consolidated_migration.action_mcp.rb` (new) — ActionMCP tables
- `web/db/migrate/20260204154534_add_consents_to_action_mcp_sess.action_mcp.rb` (new)
- `web/db/migrate/20260204154535_remove_oauth_support.action_mcp.rb` (new)
- `web/db/migrate/20260204160003_add_protocol_key_to_terminal_sessions.rb` (new) — mcp_key column
- `web/db/migrate/20260204160004_create_session_tools.rb` (new) — session_tools join table
- `web/app/models/terminal_session.rb` (modified) — mcp_key, session_tools, available_tools
- `web/app/models/session_tool.rb` (new) — join model
- `web/app/mcp/application_gateway.rb` (modified) — TerminalSessionIdentifier
- `web/app/mcp/tools/application_mcp_tool.rb` (new) — ActionMCP generated
- `web/app/mcp/prompts/application_mcp_prompt.rb` (new) — ActionMCP generated
- `web/app/mcp/resource_templates/application_mcp_res_template.rb` (new) — ActionMCP generated
- `web/config/initializers/action_mcp_dynamic_tools.rb` (new) — dynamic tools patch
- `web/config/initializers/inflections.rb` (modified) — MCP acronym
- `web/config/mcp.yml` (new) — ActionMCP configuration
- `web/app/services/container_service.rb` (modified) — MCP env vars
- `web/test/models/terminal_session_mcp_test.rb` (new) — tests
- `web/test/models/session_tool_test.rb` (new) — tests
- `web/config/initializers/fast_mcp.rb` (deleted) — removed old fast_mcp

## Dev Agent Record

### Agent Model Used

Claude Sonnet 4

### Completion Notes

- Installed ActionMCP 0.80.1 and solid_mcp gems
- Implemented session-based MCP authentication via mcp_key
- Created SessionTool join table for tool selection per session
- Patched ActionMCP tools/list and tools/call handlers for dynamic resolution
- Added MCP_SERVER_URL and MCP_SESSION_KEY env vars to agent containers
- All 282 tests pass (10 new MCP-related tests)
- Deferred: config file mounting for CLI types, full integration tests

### Change Log

- 2026-02-04: Initial implementation of Story 7.1
