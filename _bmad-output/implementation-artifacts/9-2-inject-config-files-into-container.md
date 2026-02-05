# Story 9.2: Inject Config Files into Container

Status: review

## Story

As a system,
I want to inject config files into the agent container based on `session.session_config["config_files"]`,
so that the agent CLI is properly configured before the session starts.

## Acceptance Criteria

1. **Config files written to correct paths** inside the container (e.g., `~/.claude/settings.json`, `~/.codex/config.toml`)
2. **Content sourced from** `session.session_config["config_files"]` — a path → content hash
3. **Files created during `before_exec`** phase of `AgentSessionStrategy` — after container starts, before user interacts
4. **Path expansion**: `~` expanded to the correct agent home directory (e.g., `/home/claude`, `/home/codex`) via adapter
5. **Directory creation**: parent directories created automatically if they don't exist
6. **File permissions**: correct ownership (agent user, not root)
7. **Idempotent**: re-running injection doesn't corrupt existing files
8. **Logging**: each file injection logged at info level with path and size
9. **Empty config_files**: if `session_config["config_files"]` is empty or missing, skip gracefully

## Tasks / Subtasks

- [x] Task 1: Create SessionContextService (AC: #1-6, #8)
  - [x] `SessionContextService.inject_config_files(container_id, session)`
  - [x] Read `session.config_files` (renamed accessor from Story 9.1)
  - [x] Resolve home directory from adapter: `AgentCredentialsService.for(agent_type).adapter.home_dir`
  - [x] Expand `~` to agent home directory in all paths
  - [x] For each config file: `mkdir -p` parent dir, then write content via `docker exec`
  - [x] Set correct ownership via `chown` after writing
  - [x] Log each file: `[SessionContext] Injected config file: ~/.claude/settings.json (245 bytes)`

- [x] Task 2: Integrate into AgentSessionStrategy.before_exec (AC: #3, #9)
  - [x] After credential loading (existing), add config file injection
  - [x] Call `SessionContextService.inject_config_files(container_id, session)`
  - [x] Handle empty config_files gracefully (skip, no error)

- [x] Task 3: Add per-adapter home_dir and default_config_paths (AC: #4)
  - [x] Each adapter already has `home_dir` — verified all 4 adapters
  - [x] Added `default_config_paths` class method on each adapter

- [x] Task 4: Write service tests (AC: #1-9)
  - [x] Test file injection with mock container
  - [x] Test path expansion (~ → home_dir)
  - [x] Test directory creation
  - [x] Test empty config_files (graceful skip)
  - [x] Test nil config_files (graceful skip)

## Dev Notes

### Architecture Patterns

- **Container file writing**: Use `docker exec -i container_id tee /path > /dev/null` pattern (already used in `AgentCredential.write_to_container`)
- **Strategy lifecycle**: `before_exec` is called AFTER container is healthy but BEFORE user gets terminal access — correct timing for config injection
- **Service extraction**: `SessionContextService` as standalone service — will also handle env vars (9.3) and MCP (9.4)

### Key Implementation: Execution Order in before_exec

Current `AgentSessionStrategy.before_exec`:
```ruby
def before_exec(context)
  return unless input[:credential].present?
  input[:credential].write_to_container(container_id)  # 1. Credentials
end
```

After this story:
```ruby
def before_exec(context)
  container_id = context[:container].id[0..11]
  session = TerminalSession.find(input[:session_id])

  # 1. Load credentials (existing)
  if input[:credential].present?
    input[:credential].write_to_container(container_id)
  end

  # 2. Inject config files (NEW - Story 9.2)
  SessionContextService.inject_config_files(container_id, session)
end
```

### Key Code References

- **AgentSessionStrategy.before_exec**: `web/app/services/container_strategies/agent_session_strategy.rb:65-74`
- **AgentCredential.write_to_container**: Uses `docker exec -i` to write files — reuse same pattern
- **Adapter home_dir**: `web/app/services/agents/base_adapter.rb` — `home_dir` method
- **Container exec**: `Docker::Container#exec` from docker-api gem

### Project Structure Notes

- New service: `web/app/services/session_context_service.rb`
- Modified: `web/app/services/container_strategies/agent_session_strategy.rb` — extend `before_exec`
- Tests: `web/test/services/session_context_service_test.rb`

### References

- [Source: web/app/services/container_strategies/agent_session_strategy.rb#before_exec]
- [Source: web/app/models/agent_credential.rb#write_to_container — file writing pattern]
- [Source: ai/cli_agents_deep_research.md — per-CLI config locations]

## Dev Agent Record

### Agent Model Used
Claude claude-4.6-opus (Cursor Agent)

### Debug Log References
- Docker::Container.get called once per write_file (not per exec), mocks adjusted accordingly

### Completion Notes List
- Created `SessionContextService` with `inject_config_files` — reads session.config_files, expands ~, writes via docker exec, sets chown
- Integrated into `AgentSessionStrategy.before_exec` as step 2 (after credentials)
- Added `default_config_paths` class method to all 4 adapters + BaseAdapter
- 3 tests for config file injection (write, empty skip, nil skip)
- 5 tests for adapter default_config_paths

### File List
- `web/app/services/session_context_service.rb` (new)
- `web/app/services/container_strategies/agent_session_strategy.rb` (modified)
- `web/app/services/agents/base_adapter.rb` (modified)
- `web/app/services/agents/claude_code_adapter.rb` (modified)
- `web/app/services/agents/codex_adapter.rb` (modified)
- `web/app/services/agents/gemini_cli_adapter.rb` (modified)
- `web/app/services/agents/cursor_cli_adapter.rb` (modified)
- `web/test/services/session_context_service_test.rb` (new)

### Change Log
- 2026-02-06: Story 9-2 implemented — SessionContextService.inject_config_files + adapter default_config_paths
