# Story 9.8: Full Session Context Assembly and Interactive Agents

Status: review

## Story

As a system,
I want a unified session context assembler that orchestrates all injection steps (credentials, config files, env vars, MCP config, skills, context file) and supports interactive vs non-interactive agent modes,
so that agent session startup is a single cohesive call with mode-aware CLI command generation.

## Acceptance Criteria

1. **AC1:** `SessionContextService.assemble_session_context(container_id, session, credential: nil)` orchestrates all injection steps in correct order
2. **AC2:** Assembler calls in sequence: credentials → config_files → MCP config → skills → context_file
3. **AC3:** Assembler handles missing credential gracefully (skip credential step)
4. **AC4:** `session_config` supports `"mode"` key with values: `"interactive"` (default) | `"non_interactive"`
5. **AC5:** `session_config` supports `"initial_prompt"` key for non-interactive mode task description
6. **AC6:** Each adapter implements `session_command(mode:, prompt:)` returning CLI command string:
   - Interactive: current commands (e.g., `claude`, `codex --yolo`, `gemini --yolo`, `agent`)
   - Non-interactive: commands with prompt flag (e.g., `claude -p "prompt"`, `codex -q "prompt"`, `gemini -p "prompt"`, `agent -m "prompt"`)
7. **AC7:** `AgentSessionStrategy.before_exec` delegates to `assemble_session_context` (replaces individual calls)
8. **AC8:** `AgentSessionStrategy.ttyd_command` uses adapter `session_command` with session mode and prompt
9. **AC9:** Validation: `initial_prompt` required when mode is `non_interactive`, ignored when `interactive`
10. **AC10:** Assembler logs each step completion with timing for debugging

## Tasks / Subtasks

- [x] Task 1: Extend TerminalSession with mode and initial_prompt (AC: #4, #5, #9)
  - [x] 1.1: Add `"mode"` and `"initial_prompt"` to `ALLOWED_SESSION_CONFIG_KEYS`
  - [x] 1.2: Add `mode` accessor (default: `"interactive"`)
  - [x] 1.3: Add `initial_prompt` accessor (default: nil)
  - [x] 1.4: Add validation: `initial_prompt` must be present when mode is `non_interactive`

- [x] Task 2: Add `session_command` to BaseAdapter and CLI adapters (AC: #6)
  - [x] 2.1: Add `session_command(mode:, prompt:)` to `BaseAdapter` (raises NotImplementedError)
  - [x] 2.2: `ClaudeCodeAdapter#session_command` — interactive: `claude`, non-interactive: `claude -p "prompt"`
  - [x] 2.3: `CodexAdapter#session_command` — interactive: `codex --yolo`, non-interactive: `codex -q "prompt"`
  - [x] 2.4: `GeminiCliAdapter#session_command` — interactive: `gemini --yolo`, non-interactive: `gemini -p "prompt"`
  - [x] 2.5: `CursorCliAdapter#session_command` — interactive: `agent`, non-interactive: `agent -m "prompt"`

- [x] Task 3: Create `SessionContextService.assemble_session_context` (AC: #1, #2, #3, #10)
  - [x] 3.1: Public method `assemble_session_context(container_id, session, credential: nil)`
  - [x] 3.2: Step 1: Inject credentials (if credential present) — calls `credential.write_to_container`
  - [x] 3.3: Step 2: Inject config files — calls `inject_config_files`
  - [x] 3.4: Step 3: Inject MCP config — calls `inject_mcp_config`
  - [x] 3.5: Step 4: Inject skills — calls `inject_skills`
  - [x] 3.6: Step 5: Inject context file — calls `inject_context_file`
  - [x] 3.7: Log each step with timing (start/end per step)

- [x] Task 4: Refactor AgentSessionStrategy (AC: #7, #8)
  - [x] 4.1: Replace individual calls in `before_exec` with `SessionContextService.assemble_session_context`
  - [x] 4.2: Override `ttyd_command` to use `adapter.session_command(mode:, prompt:)` from session
  - [x] 4.3: Remove `SESSION_COMMANDS` constant usage for session commands (keep for auth_setup)

- [x] Task 5: Tests (AC: #1-10)
  - [x] 5.1: TerminalSession: `mode` accessor, `initial_prompt` accessor, validation
  - [x] 5.2: Adapter tests: `session_command` for all 4 CLIs (interactive + non-interactive modes)
  - [x] 5.3: `assemble_session_context` — orchestrates all steps in order, handles missing credential
  - [x] 5.4: `assemble_session_context` — logs timing for each step
  - [x] 5.5: AgentSessionStrategy: `before_exec` delegates to assembler
  - [x] 5.6: AgentSessionStrategy: `ttyd_command` returns mode-aware command

## Dev Notes

### Architecture: Unified Assembler

Currently `AgentSessionStrategy.before_exec` has 5 individual `SessionContextService.*` calls + credential loading scattered across the method. The assembler consolidates this into a single entry point:

```ruby
# SessionContextService
def assemble_session_context(container_id, session, credential: nil)
  steps = []

  # Step 1: Credentials
  if credential.present?
    measure_step("credentials") do
      credential.write_to_container(container_id)
    end
  end

  # Step 2: Config files
  measure_step("config_files") { inject_config_files(container_id, session) }

  # Step 3: MCP config
  measure_step("mcp_config") { inject_mcp_config(container_id, session) }

  # Step 4: Skills
  measure_step("skills") { inject_skills(container_id, session) }

  # Step 5: Context file (after skills — append to same file for Gemini)
  measure_step("context_file") { inject_context_file(container_id, session) }

  Rails.logger.info("[SessionContext] Assembly complete for session #{session.id}")
end

private

def measure_step(name)
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  yield
  elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(1)
  Rails.logger.info("[SessionContext] Step '#{name}' completed in #{elapsed}ms")
end
```

### AgentSessionStrategy Refactoring

```ruby
# Before (current):
def before_exec(context)
  # ... 5 individual calls + credential loading
end

# After:
def before_exec(context)
  container_ref = context[:container] || context[:container_id]
  container_id = runtime.container_identifier(container_ref)
  raise "Container not ready for before_exec" if container_id.blank?

  session = TerminalSession.find(input[:session_id])
  SessionContextService.assemble_session_context(container_ref, session, credential: input[:credential])
end
```

### Mode-Aware CLI Commands

Each adapter generates the appropriate CLI command based on session mode:

```ruby
# BaseAdapter
def session_command(mode:, prompt: nil)
  raise NotImplementedError, "#{self.class} must implement #session_command"
end

# ClaudeCodeAdapter
def session_command(mode:, prompt: nil)
  if mode == "non_interactive" && prompt.present?
    "claude -p #{Shellwords.escape(prompt)}"
  else
    "claude"
  end
end

# CodexAdapter
def session_command(mode:, prompt: nil)
  if mode == "non_interactive" && prompt.present?
    "codex -q #{Shellwords.escape(prompt)}"
  else
    "codex --yolo"
  end
end

# GeminiCliAdapter
def session_command(mode:, prompt: nil)
  if mode == "non_interactive" && prompt.present?
    "gemini -p #{Shellwords.escape(prompt)}"
  else
    "gemini --yolo"
  end
end

# CursorCliAdapter
def session_command(mode:, prompt: nil)
  if mode == "non_interactive" && prompt.present?
    "agent -m #{Shellwords.escape(prompt)}"
  else
    "agent"
  end
end
```

### TerminalSession Extensions

```ruby
ALLOWED_SESSION_CONFIG_KEYS = %w[config_files env_vars mcp_server_ids tool_ids agent_id skill_ids mode initial_prompt].freeze

def mode
  session_config["mode"] || "interactive"
end

def initial_prompt
  session_config["initial_prompt"]
end
```

### AgentSessionStrategy.ttyd_command

```ruby
def ttyd_command
  session = TerminalSession.find(input[:session_id])
  adapter = AgentCredentialsService.for(input[:agent_type]).adapter
  adapter.session_command(mode: session.mode, prompt: session.initial_prompt)
end
```

Note: `SESSION_COMMANDS` constant stays in `AgentAuthStrategy` for auth_setup sessions. Only `AgentSessionStrategy` switches to adapter-based command generation.

### Shell Escaping

`Shellwords.escape` is used for the prompt to prevent shell injection. The prompt is passed as a single shell argument.

### Important: Prompt Length

Non-interactive prompts can be long. The TTYD_CMD env var passes through Docker, so:
- Max practical length: ~128KB (Docker env var limit)
- For very long prompts, consider writing to a file and using `cat file | claude` pattern (future enhancement)
- For now, direct flag is sufficient for typical use cases

### Files to Create/Modify

**Modified files:**
- `web/app/models/terminal_session.rb` — add `mode`, `initial_prompt` to session_config
- `web/app/services/agents/base_adapter.rb` — add `session_command`
- `web/app/services/agents/claude_code_adapter.rb` — implement `session_command`
- `web/app/services/agents/codex_adapter.rb` — implement `session_command`
- `web/app/services/agents/gemini_cli_adapter.rb` — implement `session_command`
- `web/app/services/agents/cursor_cli_adapter.rb` — implement `session_command`
- `web/app/services/session_context_service.rb` — add `assemble_session_context`, `measure_step`
- `web/app/services/container_strategies/agent_session_strategy.rb` — refactor `before_exec` and `ttyd_command`

**Modified test files:**
- `web/test/models/terminal_session_test.rb` — mode/initial_prompt tests
- `web/test/services/session_context_service_test.rb` — assemble_session_context tests

### Key Code References

- **SessionContextService** (extend): `web/app/services/session_context_service.rb`
- **BaseAdapter** (extend): `web/app/services/agents/base_adapter.rb`
- **AgentSessionStrategy** (refactor): `web/app/services/container_strategies/agent_session_strategy.rb`
- **AgentAuthStrategy** (SESSION_COMMANDS): `web/app/services/container_strategies/agent_auth_strategy.rb`
- **TerminalSession** (extend): `web/app/models/terminal_session.rb`
- **AgentCredential#write_to_container**: `web/app/models/agent_credential.rb`

### Previous Story Intelligence

Stories 9-1 through 9-7 established:
- `SessionContextService` orchestrates all container context injection with individual public methods
- `before_exec` in `AgentSessionStrategy` calls them in order: credentials → config_files → MCP → skills → context_file
- `build_env_vars` in `AgentSessionStrategy` resolves env vars separately (not in before_exec)
- All files written to home dirs (not `/workspace`) — `expand_path` handles `~` expansion
- Runtime mock pattern: `SessionContextService.instance_variable_set(:@runtime, runtime_mock)`
- `ContainerRuntime` abstraction supports Docker and Kubernetes backends
- Rubocop: `[ item ]` style for arrays, no trailing commas
- Pre-existing test failures (5) in old Docker API mocking tests — not related

### References

- [Source: web/app/services/session_context_service.rb — current injection methods]
- [Source: web/app/services/container_strategies/agent_session_strategy.rb — current before_exec]
- [Source: web/app/services/container_strategies/agent_auth_strategy.rb — SESSION_COMMANDS]
- [Source: web/app/services/agents/base_adapter.rb — adapter interface]
- [Source: web/app/models/terminal_session.rb — session_config accessors]
- [Source: ai/cli_agents_deep_research.md — CLI non-interactive modes]
- [Source: ai/workflow-architecture.md — interactive vs non-interactive modes]
- [Source: _bmad-output/implementation-artifacts/9-7-mcp-descriptions-in-session-context.md — previous story]

## Dev Agent Record

### Agent Model Used

Claude claude-4.6-opus-max-thinking

### Debug Log References

- Tests: 135 runs, 300 assertions. All new tests pass. 5 failures + 3 errors are pre-existing (old Docker API mock pattern from Stories 9.2/9.4).
- Rubocop: 0 new offenses. 1 pre-existing offense in `claude_code_adapter.rb:24` (trailing comma).

### Completion Notes List

- `TerminalSession`: Added `mode` and `initial_prompt` accessors with validation for non_interactive mode requiring initial_prompt.
- `BaseAdapter`: Added `session_command(mode:, prompt:)` abstract method.
- All 4 CLI adapters implement `session_command` with Shellwords.escape for prompt safety.
- `SessionContextService.assemble_session_context`: Unified orchestrator calling credentials → config_files → MCP → skills → context_file with per-step timing via `measure_step`.
- `AgentSessionStrategy.before_exec`: Simplified to single `assemble_session_context` call.
- `AgentSessionStrategy.ttyd_command`: Now uses `adapter.session_command` with session mode/prompt instead of `SESSION_COMMANDS` constant.
- Updated 2 pre-existing before_exec tests that broke due to refactoring (now test assembler delegation).

### File List

- `web/app/models/terminal_session.rb` — mode, initial_prompt accessors + validation
- `web/app/services/agents/base_adapter.rb` — session_command abstract method
- `web/app/services/agents/claude_code_adapter.rb` — session_command implementation
- `web/app/services/agents/codex_adapter.rb` — session_command implementation
- `web/app/services/agents/gemini_cli_adapter.rb` — session_command implementation
- `web/app/services/agents/cursor_cli_adapter.rb` — session_command implementation
- `web/app/services/session_context_service.rb` — assemble_session_context + measure_step
- `web/app/services/container_strategies/agent_session_strategy.rb` — before_exec + ttyd_command refactored
- `web/test/models/terminal_session_test.rb` — mode/prompt tests
- `web/test/services/session_context_service_test.rb` — session_command + assembler tests
- `web/test/services/container_strategies/agent_session_strategy_test.rb` — before_exec + ttyd_command tests
