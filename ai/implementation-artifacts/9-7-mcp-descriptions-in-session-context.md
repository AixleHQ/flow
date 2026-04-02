# Story 9.7: MCP Descriptions in Session Context

Status: done

## Story

As a system,
I want to generate descriptions of available MCP servers and tools, then inject them into the CLI-specific context file,
so that the AI agent understands what external capabilities are available and how to use them.

## Acceptance Criteria

1. **AC1:** `SessionContextService.inject_context_file(container_id, session)` generates and writes the CLI context file
2. **AC2:** Context file path per CLI adapter via `context_file_path` method (home dir, not workspace):
   - Claude Code: `~/.claude/CLAUDE.md` → `/home/claude/.claude/CLAUDE.md`
   - Codex: `~/.codex/AGENTS.md` → `/home/codex/.codex/AGENTS.md`
   - Gemini CLI: `~/.gemini/GEMINI.md` → `/home/gemini/.gemini/GEMINI.md`
   - Cursor CLI: `~/.cursor/rules/.cursorrules` → `/home/cursor/.cursor/rules/.cursorrules`
3. **AC3:** Context file includes **MCP server descriptions**: for each MCP server in session (from `mcp_server_ids`), generate a section with `display_name`, `description`, and `name` (the MCP identifier the agent uses)
4. **AC4:** Context file includes **tool descriptions**: for each tool available in session (from `available_tools`), generate a section with `display_name`, `description`, and `name` (the MCP tool name the agent calls)
5. **AC5:** Context file includes **agent persona**: if `session.configured_agent_id` is set, load Agent and include `to_system_prompt` content
6. **AC6:** Context file uses append strategy — read existing content first (from Story 9.2 config_files injection or 9.6 skills), append new sections
7. **AC7:** Empty MCP servers / tools / agent — skip those sections gracefully (no empty headings)
8. **AC8:** Context file injection called in `AgentSessionStrategy.before_exec` as Step 5 (after skills injection)
9. **AC9:** Internal aixle-tools MCP server description always included (it's always present in session)

## Tasks / Subtasks

- [x] Task 1: Add `context_file_path` to BaseAdapter and CLI adapters (AC: #2)
  - [x] 1.1: Add `context_file_path` to `BaseAdapter` (default: nil)
  - [x] 1.2: `ClaudeCodeAdapter#context_file_path` → `~/.claude/CLAUDE.md`
  - [x] 1.3: `CodexAdapter#context_file_path` → `~/.codex/AGENTS.md`
  - [x] 1.4: `GeminiCliAdapter#context_file_path` → `~/.gemini/GEMINI.md`
  - [x] 1.5: `CursorCliAdapter#context_file_path` → `~/.cursor/rules/.cursorrules`

- [x] Task 2: Add context content builders to SessionContextService (AC: #3, #4, #5, #9)
  - [x] 2.1: `build_mcp_descriptions(session)` — resolve MCP servers, format as markdown sections
  - [x] 2.2: `build_tool_descriptions(session)` — resolve available tools, format as markdown sections
  - [x] 2.3: `build_agent_persona(session)` — load Agent from `configured_agent_id`, call `to_system_prompt`
  - [x] 2.4: `build_context_content(session)` — orchestrator that combines all sections

- [x] Task 3: Add `inject_context_file` to SessionContextService (AC: #1, #6, #7)
  - [x] 3.1: `inject_context_file(container_id, session)` — build content, read existing, append, write
  - [x] 3.2: Handle append: read existing file content from container (may have config_files or skills content), append context sections
  - [x] 3.3: Skip gracefully when no content to add (no MCP, no tools, no agent)

- [x] Task 4: Integrate into AgentSessionStrategy (AC: #8)
  - [x] 4.1: Add Step 5 in `before_exec`: `SessionContextService.inject_context_file(container_ref, session)`
  - [x] 4.2: Place after skills injection (Step 4)

- [x] Task 5: Tests (AC: #1-9)
  - [x] 5.1: Adapter tests: `context_file_path` for all 4 CLIs + base
  - [x] 5.2: `build_mcp_descriptions` — formats server descriptions, includes aixle-tools
  - [x] 5.3: `build_tool_descriptions` — formats tool descriptions, handles empty
  - [x] 5.4: `build_agent_persona` — loads Agent, handles missing agent_id
  - [x] 5.5: `inject_context_file` — writes to correct path, appends to existing, skips when empty

## Dev Notes

### Architecture Pattern — follows inject_skills exactly

Same `SessionContextService` → adapter `{ path => content }` pattern from Stories 9.4 and 9.6.

### Context File Content Structure

Each context file will contain concatenated sections:

```markdown
# Agent Persona (if agent configured)
{agent.to_system_prompt content}

## Available MCP Servers

### aixle-tools
Internal Aixle tools server. Provides project-specific tools configured for this session.

### tavily
Tavily web search API. Provides real-time web search capabilities.

### context7
Context7 documentation search. Retrieves up-to-date library documentation.

## Available Tools

### web-search
Web Search — Search the web for real-time information.
Parameters: query (string, required), max_results (integer)

### create-github-pr
Create GitHub PR — Creates a pull request in the configured repository.
Parameters: title (string, required), body (string), base_branch (string)
```

### Content Builders — Private Methods in SessionContextService

**MCP Descriptions:**
```ruby
def build_mcp_descriptions(session)
  servers = build_all_servers(session)  # reuse existing method — includes aixle-tools
  return "" if servers.empty?

  lines = ["## Available MCP Servers\n"]
  servers.each do |server|
    lines << "### #{server.name}"
    # For full MCPServer records, use display_name and description
    if server.respond_to?(:display_name) && server.display_name.present?
      lines << server.display_name
    end
    if server.respond_to?(:description) && server.description.present?
      lines << server.description
    end
    lines << ""
  end
  lines.join("\n")
end
```

**Tool Descriptions:**
```ruby
def build_tool_descriptions(session)
  tools = session.available_tools.to_a
  return "" if tools.empty?

  lines = ["## Available Tools\n"]
  tools.each do |tool|
    lines << "### #{tool.name}"
    desc = [tool.display_name, tool.description].compact.join(" — ")
    lines << desc if desc.present?
    # Include input schema summary if present
    if tool.input_schema.present? && tool.input_schema["properties"].present?
      params = tool.input_schema["properties"].map { |k, v| "#{k} (#{v['type']})" }.join(", ")
      lines << "Parameters: #{params}" if params.present?
    end
    lines << ""
  end
  lines.join("\n")
end
```

**Agent Persona:**
```ruby
def build_agent_persona(session)
  agent_id = session.configured_agent_id
  return "" if agent_id.blank?

  agent = Agent.find_by(id: agent_id)
  return "" unless agent

  agent.to_system_prompt
end
```

**Orchestrator:**
```ruby
def build_context_content(session)
  sections = []

  persona = build_agent_persona(session)
  sections << persona if persona.present?

  mcp = build_mcp_descriptions(session)
  sections << mcp if mcp.present?

  tools = build_tool_descriptions(session)
  sections << tools if tools.present?

  sections.join("\n\n")
end
```

### inject_context_file — Append Strategy

The context file may already have content from:
- Story 9.2: `config_files` injection (user can pre-configure CLAUDE.md content)
- Story 9.6: skills injection (Gemini appends skills to GEMINI.md)

Must read existing content and append:
```ruby
def inject_context_file(container_id, session)
  content = build_context_content(session)
  return if content.blank?

  adapter = adapter_for(session)
  path = adapter.context_file_path
  return if path.blank?

  expanded = expand_path(path, adapter.home_dir)
  existing = read_file(container_id, expanded) || ""

  separator = existing.present? ? "\n\n---\n\n" : ""
  final_content = existing + separator + content

  write_file(container_id, expanded, final_content, adapter.tmpfs_uid)
  Rails.logger.info("[SessionContext] Injected context file: #{path} (#{content.bytesize} bytes added)")
end
```

### AgentSessionStrategy Integration

```ruby
# In AgentSessionStrategy.before_exec:
# Step 1: inject config files (Story 9.2)
# Step 2: resolve env vars (Story 9.3)
# Step 3: inject MCP config (Story 9.4)
# Step 4: inject skills (Story 9.6)
# Step 5: inject context file (Story 9.7) ← NEW
SessionContextService.inject_context_file(container_ref, session)
```

### BaseAdapter Extension

```ruby
# Path to CLI-specific context file (auto-read by CLI at startup)
# @return [String, nil] nil if CLI doesn't support context files
def context_file_path
  nil
end
```

### Aixle-Tools Internal MCP Description

The internal aixle-tools server is always present. Its description should clarify:
- It provides dynamically configured tools for this session
- Tools are accessed via MCP tool calls (the agent doesn't need to know the transport details)
- The tool list is auto-populated from the `tools/list` MCP endpoint

```ruby
# In build_mcp_descriptions, special handling for aixle-tools:
if server.name == "aixle-tools"
  lines << "Internal tools server. Provides project-specific tools configured for this session."
  lines << "Call tools via MCP — use `tools/list` to see available tools."
end
```

### Files to Create/Modify

**Modified files:**
- `web/app/services/session_context_service.rb` — add `inject_context_file`, `build_context_content`, `build_mcp_descriptions`, `build_tool_descriptions`, `build_agent_persona`
- `web/app/services/agents/base_adapter.rb` — add `context_file_path`
- `web/app/services/agents/claude_code_adapter.rb` — implement `context_file_path`
- `web/app/services/agents/codex_adapter.rb` — implement `context_file_path`
- `web/app/services/agents/gemini_cli_adapter.rb` — implement `context_file_path`
- `web/app/services/agents/cursor_cli_adapter.rb` — implement `context_file_path`
- `web/app/services/container_strategies/agent_session_strategy.rb` — add Step 5

**Modified test files:**
- `web/test/services/session_context_service_test.rb` — tests for inject_context_file, builders

### Key Code References

- **SessionContextService** (extend): `web/app/services/session_context_service.rb`
- **inject_skills pattern** (identical): `inject_skills` method with append strategy
- **BaseAdapter** (extend): `web/app/services/agents/base_adapter.rb`
- **Agent model** (to_system_prompt): `web/app/models/agent.rb`
- **MCPServer model** (display_name, description): `web/app/models/mcp_server.rb`
- **Tool model** (display_name, description, input_schema): `web/app/models/tool.rb`
- **TerminalSession** (available_tools, configured_agent_id): `web/app/models/terminal_session.rb`
- **build_all_servers** (reuse for MCP list): `SessionContextService.build_all_servers`
- **AgentSessionStrategy.before_exec**: `web/app/services/container_strategies/agent_session_strategy.rb`

### Previous Story Intelligence

Stories 9-1 through 9-6 established:
- `SessionContextService` orchestrates all container context injection
- Adapter pattern: `{ path => content }` hash returned by adapter methods
- `write_file` / `read_file` helpers for container filesystem
- `expand_path` replaces `~` with agent home_dir
- Gemini uses GEMINI.md as context file — skills already append to it (Story 9.6)
- `build_all_servers(session)` already resolves MCP servers (internal + external)
- `session.available_tools` resolves tools (from tool_ids or project fallback)
- `session.configured_agent_id` references Agent record
- `Agent#to_system_prompt` builds formatted persona text
- Runtime mock pattern: `SessionContextService.instance_variable_set(:@runtime, runtime_mock)`
- Rubocop enforces `Layout/SpaceInsideArrayLiteralBrackets` — use `[ item ]` not `[item]`

### Important: Gemini GEMINI.md Overlap

Gemini CLI's `skill_files` already writes to `~/.gemini/GEMINI.md` with `:append` strategy. The `inject_context_file` for Gemini also targets `~/.gemini/GEMINI.md`. This is fine — inject_context_file runs AFTER inject_skills (Step 5 vs Step 4), and uses the same append pattern (read existing → append new content). The final GEMINI.md will contain: `[config_files content] + [skills sections] + [context sections]`.

### Home Directory Paths (not workspace)

All context/skill files are written to home directories to keep `/workspace` clean for user assets and outputs:
- Claude: `/home/claude/.claude/` (skills + CLAUDE.md)
- Codex: `/home/codex/.codex/` (skills + AGENTS.md)
- Gemini: `/home/gemini/.gemini/` (GEMINI.md with skills and context appended)
- Cursor: `/home/cursor/.cursor/rules/` (skills + .cursorrules)

Each CLI reads user-scoped config from its home directory at startup. The `expand_path` helper in SessionContextService handles `~` → `home_dir` expansion automatically.

### References

- [Source: web/app/services/session_context_service.rb — injection pattern]
- [Source: web/app/services/agents/base_adapter.rb — adapter interface]
- [Source: web/app/models/agent.rb — to_system_prompt]
- [Source: web/app/models/mcp_server.rb — display_name, description fields]
- [Source: web/app/models/tool.rb — display_name, description, input_schema]
- [Source: web/app/models/terminal_session.rb — available_tools, configured_agent_id]
- [Source: ai/cli_agents_deep_research.md — context management per CLI]
- [Source: _bmad-output/implementation-artifacts/9-6-inject-agent-skills-into-container.md — previous story]

## Dev Agent Record

### Agent Model Used

Claude claude-4.6-opus

### Debug Log References

- Test run: 22 runs, 75 assertions, 0 failures, 0 errors (Story 9.7 tests)
- Rubocop: 0 new offenses (1 pre-existing in claude_code_adapter.rb:24)
- Pre-existing test failures (5): old Docker API mocking in Stories 9.2/9.4 tests (not related)

### Completion Notes List

- Added `context_file_path` to `BaseAdapter` (nil) and all 4 CLI adapters with home directory paths
- Added `inject_context_file` to `SessionContextService` with append strategy (reads existing, adds separator, appends)
- Added private builders: `build_context_content`, `build_agent_persona`, `build_mcp_descriptions`, `build_tool_descriptions`
- `build_mcp_descriptions` resolves MCPServer records directly (not via `build_all_servers`) to preserve `display_name`/`description`
- aixle-tools always included with hardcoded description
- Integrated as Step 5 in `AgentSessionStrategy.before_exec` (after skills injection)
- 22 new tests covering all ACs: adapter paths, builders, inject_context_file with all 4 CLIs, persona, tools, append

### File List

**Modified:**
- `web/app/services/agents/base_adapter.rb` — added `context_file_path`
- `web/app/services/agents/claude_code_adapter.rb` — implemented `context_file_path`
- `web/app/services/agents/codex_adapter.rb` — implemented `context_file_path`
- `web/app/services/agents/gemini_cli_adapter.rb` — implemented `context_file_path`
- `web/app/services/agents/cursor_cli_adapter.rb` — implemented `context_file_path`
- `web/app/services/session_context_service.rb` — added `inject_context_file` + content builders
- `web/app/services/container_strategies/agent_session_strategy.rb` — added Step 5
- `web/test/services/session_context_service_test.rb` — added 22 tests for Story 9.7
