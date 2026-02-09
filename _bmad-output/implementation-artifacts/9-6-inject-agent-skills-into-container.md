# Story 9.6: Inject Agent Skills into Container

Status: review

## Story

As a system,
I want to inject selected skills into the agent container at session start,
so that the AI agent CLI has access to domain-specific instructions in its native skill format.

## Acceptance Criteria

1. **AC1:** `skill_ids` added to `TerminalSession.ALLOWED_SESSION_CONFIG_KEYS` with accessor
2. **AC2:** `SessionContextService.inject_skills(container_id, session)` resolves skills from `session.skill_ids` and writes them to container
3. **AC3:** Skills resolved via `Skill.merged_for_project(session.project)` filtered by `skill_ids` — includes internal + company + project, project overrides company by name
4. **AC4:** Per-CLI skill format and path:
   - **Claude Code**: Each skill written as `/workspace/.claude/skills/<name>.md` (content only)
   - **Codex**: Each skill written as `/workspace/.codex/skills/<name>/SKILL.md` with YAML front matter (`name`, `description`)
   - **Gemini CLI**: Each skill appended as a section in `/workspace/GEMINI.md` (markdown heading + content)
   - **Cursor CLI**: Each skill written as `/workspace/.cursor/skills/<name>.md` (content only)
5. **AC5:** Each adapter implements `skill_files(skills)` method returning `{ path => content }` hash
6. **AC6:** Skill injection called in `AgentSessionStrategy.before_exec` after MCP config injection (Step 4)
7. **AC7:** Empty `skill_ids` or `[]` — skip gracefully (no error)
8. **AC8:** Missing or invalid skill IDs logged as warnings, not errors (skip gracefully)
9. **AC9:** Skill content preserved as-is for Claude/Cursor; wrapped in YAML front matter for Codex; concatenated with headers for Gemini

## Tasks / Subtasks

- [x] Task 1: Add `skill_ids` to TerminalSession (AC: #1)
  - [x] 1.1: Add `skill_ids` to `ALLOWED_SESSION_CONFIG_KEYS`
  - [x] 1.2: Add `skill_ids` accessor method (returns `session_config["skill_ids"] || []`)

- [x] Task 2: Add `skill_files` to BaseAdapter and CLI adapters (AC: #4, #5, #9)
  - [x] 2.1: Add `skill_files(skills)` to `BaseAdapter` (default: empty hash)
  - [x] 2.2: `ClaudeCodeAdapter#skill_files` — write `/workspace/.claude/skills/<name>.md`
  - [x] 2.3: `CodexAdapter#skill_files` — write `/workspace/.codex/skills/<name>/SKILL.md` with YAML front matter
  - [x] 2.4: `GeminiCliAdapter#skill_files` — concatenate all skills into single `/workspace/GEMINI.md` append
  - [x] 2.5: `CursorCliAdapter#skill_files` — write `/workspace/.cursor/skills/<name>.md`

- [x] Task 3: Add `inject_skills` to SessionContextService (AC: #2, #3, #7, #8)
  - [x] 3.1: `inject_skills(container_id, session)` — resolve skill_ids, get merged skills, call adapter.skill_files, write files
  - [x] 3.2: Resolve skills: load `Skill.where(id: skill_ids)`, handle missing/invalid IDs with warnings
  - [x] 3.3: Write each file using existing `write_file` helper

- [x] Task 4: Integrate into AgentSessionStrategy (AC: #6)
  - [x] 4.1: Add Step 4 in `before_exec`: `SessionContextService.inject_skills(container_ref, session)`
  - [x] 4.2: Place after MCP config injection (Step 3)

- [x] Task 5: Tests (AC: #1-9)
  - [x] 5.1: TerminalSession: `skill_ids` accessor and validation
  - [x] 5.2: Adapter tests: `skill_files` for all 4 CLI types — correct paths, content format
  - [x] 5.3: SessionContextService: `inject_skills` — writes files, handles empty/missing IDs, logs warnings
  - [x] 5.4: Integration: `before_exec` calls `inject_skills` after MCP config

## Dev Notes

### Architecture Pattern — follow SessionContextService exactly

This follows the **identical pattern** to Story 9.4 (MCP config injection). Every decision matches existing code.

**SessionContextService pattern** (see `inject_mcp_config`):
```ruby
# == Story 9.6: Skill Injection ==

def inject_skills(container_id, session)
  skills = resolve_skills(session)
  return if skills.empty?

  adapter = adapter_for(session)
  skill_files = adapter.skill_files(skills)
  return if skill_files.blank?

  skill_files.each do |path, content|
    expanded = expand_path(path, adapter.home_dir)
    write_file(container_id, expanded, content, adapter.tmpfs_uid)
    Rails.logger.info("[SessionContext] Injected skill: #{path} (#{content.bytesize} bytes)")
  end
end
```

**Skill resolution** (like `resolve_mcp_servers`):
```ruby
def resolve_skills(session)
  ids = session.skill_ids
  return [] if ids.blank?

  skills = Skill.where(id: ids).to_a
  found_ids = skills.map(&:id)
  missing = ids - found_ids

  missing.each { |id| Rails.logger.warn("[SessionContext] Skill #{id} not found, skipping") }
  skills
end
```

**BaseAdapter extension** (new method alongside `mcp_config`):
```ruby
# Generate skill files for this CLI.
# @param skills [Array<Skill>] resolved Skill records
# @return [Hash<String, String>] { path => content }
def skill_files(skills)
  {}
end
```

### Per-CLI Skill Format Details

**Claude Code** (`/workspace/.claude/skills/<name>.md`):
- Claude Code supports a "Skills" feature that loads markdown files on-demand
- Official docs say skills are stored in the claude config directory
- Best practice: write to `/workspace/.claude/skills/<name>.md` (project-scoped)
- Content: raw markdown, no special formatting needed
```ruby
def skill_files(skills)
  files = {}
  skills.each do |skill|
    next if skill.content.blank?
    files["/workspace/.claude/skills/#{skill.name}.md"] = skill.content
  end
  files
end
```

**Codex** (`/workspace/.codex/skills/<name>/SKILL.md`):
- Well-documented: `SKILL.md` with YAML front matter in `.codex/skills/<name>/` directory
- Skills can be invoked explicitly (`$skill-name`) or auto-selected
- Format: YAML front matter (`name`, `description`) + markdown body
```ruby
def skill_files(skills)
  files = {}
  skills.each do |skill|
    next if skill.content.blank?
    front_matter = "---\nname: #{skill.name}\ndescription: #{(skill.description || skill.title || skill.name).to_json}\n---\n\n"
    files["/workspace/.codex/skills/#{skill.name}/SKILL.md"] = front_matter + skill.content
  end
  files
end
```

**Gemini CLI** — append to `/workspace/GEMINI.md`:
- Gemini uses `GEMINI.md` as context file (like Claude's `CLAUDE.md`)
- No separate skill directories documented
- Strategy: append all skills as sections to GEMINI.md (`:append` strategy)
- Use `write_mcp_file` with `:append_toml` strategy adapted, or simple string append
```ruby
def skill_files(skills)
  sections = skills.filter_map do |skill|
    next if skill.content.blank?
    "## Skill: #{skill.title || skill.name}\n\n#{skill.content}"
  end
  return {} if sections.empty?
  { "/workspace/GEMINI.md" => "\n\n" + sections.join("\n\n---\n\n") + "\n" }
end
```
Note: Use append strategy when writing — read existing GEMINI.md first, then append skills section.

**Cursor CLI** (`/workspace/.cursor/skills/<name>.md`):
- Cursor supports skills but exact file format not fully documented
- Follow same pattern as Claude: simple markdown files in skill directory
```ruby
def skill_files(skills)
  files = {}
  skills.each do |skill|
    next if skill.content.blank?
    files["/workspace/.cursor/skills/#{skill.name}.md"] = skill.content
  end
  files
end
```

### Gemini Append Strategy

For Gemini, skills are appended to GEMINI.md (which may already have content from other context injection). Need to read existing content first:
```ruby
# In SessionContextService.inject_skills, special handling for Gemini:
skill_files.each do |path, content|
  expanded = expand_path(path, adapter.home_dir)
  if adapter.skill_merge_strategy == :append
    existing = read_file(container_id, expanded) || ""
    write_file(container_id, expanded, existing + content, adapter.tmpfs_uid)
  else
    write_file(container_id, expanded, content, adapter.tmpfs_uid)
  end
end
```

Or simpler: add a `skill_merge_strategy` method to BaseAdapter (default `:fresh`, Gemini returns `:append`).

### AgentSessionStrategy Integration

```ruby
# In AgentSessionStrategy.before_exec:
# Step 1: inject config files (Story 9.2)
# Step 2: resolve env vars (Story 9.3)
# Step 3: inject MCP config (Story 9.4)
# Step 4: inject skills (Story 9.6) ← NEW
SessionContextService.inject_skills(container_ref, session)
```

### TerminalSession Changes

```ruby
# Add to ALLOWED_SESSION_CONFIG_KEYS:
ALLOWED_SESSION_CONFIG_KEYS = %w[config_files env_vars mcp_server_ids tool_ids agent_id skill_ids].freeze

# Add accessor:
def skill_ids
  session_config["skill_ids"] || []
end
```

### Files to Create/Modify

**Modified files:**
- `web/app/models/terminal_session.rb` — add `skill_ids` to ALLOWED_SESSION_CONFIG_KEYS + accessor
- `web/app/services/session_context_service.rb` — add `inject_skills`, `resolve_skills` methods
- `web/app/services/agents/base_adapter.rb` — add `skill_files`, `skill_merge_strategy` methods
- `web/app/services/agents/claude_code_adapter.rb` — implement `skill_files`
- `web/app/services/agents/codex_adapter.rb` — implement `skill_files` (YAML front matter)
- `web/app/services/agents/gemini_cli_adapter.rb` — implement `skill_files` (append to GEMINI.md)
- `web/app/services/agents/cursor_cli_adapter.rb` — implement `skill_files`

**New test files:**
- `web/test/services/session_context_service/inject_skills_test.rb` (or extend existing test)

**Modified test files:**
- Existing SessionContextService tests — add skill injection tests
- Existing adapter tests — add skill_files tests

### Key Code References

- **SessionContextService** (pattern to follow): `web/app/services/session_context_service.rb`
- **MCP injection** (identical pattern): `inject_mcp_config` method in SessionContextService
- **BaseAdapter** (extend): `web/app/services/agents/base_adapter.rb`
- **ClaudeCodeAdapter** (pattern): `web/app/services/agents/claude_code_adapter.rb`
- **CodexAdapter**: `web/app/services/agents/codex_adapter.rb`
- **GeminiCliAdapter**: `web/app/services/agents/gemini_cli_adapter.rb`
- **CursorCliAdapter**: `web/app/services/agents/cursor_cli_adapter.rb`
- **TerminalSession**: `web/app/models/terminal_session.rb`
- **Skill model**: `web/app/models/skill.rb`
- **CLI research** (skill formats): `ai/cli_agents_deep_research.md` (Skills row)
- **AgentSessionStrategy**: search for `before_exec` in strategies directory

### Previous Story Intelligence

Stories 9-1 through 9-5 established:
- `session_config` JSONB on TerminalSession with accessor pattern (config_files, env_vars, mcp_server_ids, tool_ids, agent_id)
- `SessionContextService` as orchestrator: `inject_config_files` → `resolve_env_vars` → `inject_mcp_config`
- Per-CLI adapter pattern: each adapter returns `{ path => content }` hash, service writes files
- `write_file` helper: uses `ContainerRuntime.copy_to` (tar stream), then `chown`
- `expand_path` helper: replaces `~` with adapter.home_dir
- MCP merge strategies: `:fresh` (Claude/Cursor), `:merge_json` (Gemini), `:append_toml` (Codex)
- Skill model: internal/custom kind, polymorphic scope (Company/Project), `merged_for_project` with scope_indicator
- Name format: `/\A[a-z][a-z0-9_-]*\z/` — safe for filesystem paths
- Rubocop enforces `Layout/SpaceInsideArrayLiteralBrackets`

### CLI Skills Research Summary (from ai/cli_agents_deep_research.md)

| CLI | Skill Support | File Location | Format |
|-----|--------------|---------------|--------|
| Claude Code | Supported, loads on-demand | Config dir (CLAUDE_CONFIG_DIR) | Not fully documented; use `.claude/skills/<name>.md` |
| Codex | Well-documented | `.codex/skills/<name>/SKILL.md` | YAML front matter + markdown |
| Gemini CLI | Via extensions or GEMINI.md | `~/.gemini/extensions/` or GEMINI.md | Markdown sections |
| Cursor CLI | Exists per docs snippet | Not fully documented; use `.cursor/skills/<name>.md` | Markdown files |

### References

- [Source: web/app/services/session_context_service.rb — injection pattern]
- [Source: web/app/services/agents/base_adapter.rb — adapter interface]
- [Source: web/app/services/agents/claude_code_adapter.rb — mcp_config pattern]
- [Source: ai/cli_agents_deep_research.md — skills per CLI]
- [Source: web/app/models/skill.rb — skill model]
- [Source: web/app/models/terminal_session.rb — session_config pattern]
- [Source: _bmad-output/implementation-artifacts/9-4-connect-mcp-servers-to-session.md — previous story]
- [Source: _bmad-output/implementation-artifacts/9-5-skills-crud-with-scoping.md — skill CRUD]

## Dev Agent Record

### Agent Model Used

Claude claude-4.6-opus

### Debug Log References

- 20 tests, 53 assertions, 0 failures, 0 errors
- Rubocop: 0 offenses on modified files
- Pre-existing failures in 9.2/9.4 container mock tests (Docker::Container mocks outdated after runtime refactor)

### Completion Notes List

- Added `skill_ids` to `TerminalSession.ALLOWED_SESSION_CONFIG_KEYS` with accessor
- Added `skill_files(skills)` and `skill_merge_strategy` to `BaseAdapter` interface
- Implemented `skill_files` for all 4 CLI adapters:
  - Claude Code: `/workspace/.claude/skills/<name>.md` (raw markdown)
  - Codex: `/workspace/.codex/skills/<name>/SKILL.md` (YAML front matter + markdown)
  - Gemini CLI: appended to `/workspace/GEMINI.md` (markdown sections, `:append` strategy)
  - Cursor CLI: `/workspace/.cursor/skills/<name>.md` (raw markdown)
- Added `inject_skills` + `resolve_skills` to `SessionContextService` following `inject_mcp_config` pattern
- Gemini append strategy: reads existing GEMINI.md, appends skills sections
- Integrated as Step 4 in `AgentSessionStrategy.before_exec` (after MCP config)
- Skills with blank content skipped; missing skill IDs logged as warnings

### File List

**Modified:**
- `web/app/models/terminal_session.rb`
- `web/app/services/session_context_service.rb`
- `web/app/services/agents/base_adapter.rb`
- `web/app/services/agents/claude_code_adapter.rb`
- `web/app/services/agents/codex_adapter.rb`
- `web/app/services/agents/gemini_cli_adapter.rb`
- `web/app/services/agents/cursor_cli_adapter.rb`
- `web/app/services/container_strategies/agent_session_strategy.rb`
- `web/test/models/terminal_session_test.rb`
- `web/test/services/session_context_service_test.rb`
