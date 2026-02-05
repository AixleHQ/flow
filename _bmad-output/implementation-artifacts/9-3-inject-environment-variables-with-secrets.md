# Story 9.3: Inject Environment Variables with Secrets

Status: ready-for-dev

## Story

As a system,
I want to inject environment variables (with resolved secrets from ConfigItem) into the agent container,
so that the agent has required API keys and credentials at startup.

## Acceptance Criteria

1. **Env vars from `session.session_config["env_vars"]`** set in container environment at creation time
2. **Secret resolution**: values with `config_item:SECRET_NAME` syntax resolved to actual decrypted values via `ConfigItem.effective_for_project`
3. **Direct values**: env vars with plain string values passed as-is
4. **No secret leakage**: resolved secret values never logged, only env var names logged
5. **Existing env vars preserved**: new vars merged with existing env vars from `AgentSessionStrategy.build_env_vars` (MCP_SERVER_URL, SESSION_TYPE, etc.)
6. **Missing secret handling**: if referenced ConfigItem doesn't exist, log warning and skip that var (don't fail entire session)
7. **Empty env_vars**: if `session_config["env_vars"]` is empty or missing, skip gracefully

## Tasks / Subtasks

- [ ] Task 1: Add env var resolution to SessionContextService (AC: #1-3, #6)
  - [ ] `SessionContextService.resolve_env_vars(session)` → returns `{ "KEY" => "value" }` hash
  - [ ] Read `session.session_env_vars` (helper from Story 9.1)
  - [ ] Parse value syntax: `config_item:NAME` → look up via `ConfigItem.effective_for_project(session.project)`
  - [ ] Plain string values → pass through as-is
  - [ ] Handle missing ConfigItem: log warning, skip that key

- [ ] Task 2: Integrate into AgentSessionStrategy.build_env_vars (AC: #5, #7)
  - [ ] After existing env vars (SESSION_TYPE, MCP_SERVER_URL, etc.), append resolved session context env vars
  - [ ] Load session from `TerminalSession.find(input[:session_id])`
  - [ ] Call `SessionContextService.resolve_env_vars(session)`
  - [ ] Append each resolved var as `"KEY=value"` to the env vars array
  - [ ] Skip if no env_vars configured

- [ ] Task 3: Secure logging (AC: #4)
  - [ ] Log: `[SessionContext] Injecting env vars: API_KEY, ANTHROPIC_API_KEY (2 vars)`
  - [ ] NEVER log resolved values
  - [ ] Log warning for missing: `[SessionContext] ConfigItem 'MISSING_KEY' not found, skipping`

- [ ] Task 4: Write tests (AC: #1-7)
  - [ ] Test direct value passthrough
  - [ ] Test config_item:SECRET resolution with mock ConfigItem
  - [ ] Test missing ConfigItem handling (skip, don't fail)
  - [ ] Test empty env_vars (graceful skip)
  - [ ] Test no secret values in log output

## Dev Notes

### Architecture Patterns

- **Env var timing**: Env vars are set at container CREATION time via `build_env_vars` (not at exec time like config files). Docker container env vars are immutable after creation. Critical difference from config file injection!
- **ConfigItem resolution**: Use `ConfigItem.effective_for_project(project)` which already handles company + project merge with proper decryption
- **Syntax**: `config_item:API_KEY` references ConfigItem by name

### Key Implementation: build_env_vars Timing

```ruby
# AgentSessionStrategy inherits AgentAuthStrategy
# build_env_vars is called during before_create → used in Docker::Container.create
# Env vars must be resolved BEFORE container creation

def build_env_vars
  base_vars = super  # From AgentAuthStrategy: SESSION_TYPE, AGENT_TYPE, etc.

  # Add MCP vars (existing)
  base_vars += ["MCP_SERVER_URL=...", "MCP_SESSION_KEY=..."]

  # Add agent-specific vars from credential metadata (existing)
  # ...

  # NEW: Add session context env vars (Story 9.3)
  session = TerminalSession.find(input[:session_id])
  context_vars = SessionContextService.resolve_env_vars(session)
  context_vars.each { |k, v| base_vars << "#{k}=#{v}" }

  base_vars
end
```

### ConfigItem Reference Syntax

```json
{
  "ANTHROPIC_API_KEY": "config_item:ANTHROPIC_API_KEY",
  "WORKSPACE": "/workspace",
  "NODE_ENV": "production"
}
```

### Key Code References

- **build_env_vars**: `web/app/services/container_strategies/agent_session_strategy.rb:32-56`
- **ConfigItem.effective_for_project**: `web/app/models/config_item.rb:62-68` — returns `{ name => decrypted_value }`
- **AgentAuthStrategy.build_env_vars**: Base env vars (SESSION_TYPE, AGENT_TYPE, USER_ID, etc.)

### Project Structure Notes

- Modified: `web/app/services/session_context_service.rb` — add `resolve_env_vars` method
- Modified: `web/app/services/container_strategies/agent_session_strategy.rb` — extend `build_env_vars`
- Tests: `web/test/services/session_context_service_test.rb` — extend with env var tests

### References

- [Source: web/app/services/container_strategies/agent_session_strategy.rb#build_env_vars]
- [Source: web/app/models/config_item.rb#effective_for_project]
- [Source: ai/cli_agents_deep_research.md — per-CLI auth env vars]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
