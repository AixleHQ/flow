# Story 33.2: BmadMethodInjector — Install BMAD in Container

Status: ready-for-dev

## Story

As a **developer using BMAD**,
I want the system to automatically install BMAD Method in my container when I enable the checkbox,
so that slash-commands and BMAD workflows are available without any manual setup.

## Acceptance Criteria

1. **Given** a session with `bmad_enabled: true` and agent_type `cursor_cli`
   **When** `BmadMethodInjector#inject!` is called
   **Then** the system executes `npx bmad-method install` with `--tools cursor` and all required flags

2. **Given** agent_type is `claude_code`
   **When** BmadMethodInjector resolves the BMAD tools flag
   **Then** the `--tools` flag is `claude-code`

3. **Given** agent_type is `codex`
   **When** BmadMethodInjector resolves the BMAD tools flag
   **Then** the `--tools` flag is `codex`

4. **Given** agent_type is `gemini_cli`
   **When** BmadMethodInjector resolves the BMAD tools flag
   **Then** the `--tools` flag is `gemini`

5. **Given** custom modules `["bmm", "cis", "bmb"]` are specified
   **When** BmadMethodInjector builds the install command
   **Then** the `--modules` flag is `bmm,cis,bmb`

6. **Given** the user has `preferred_agent_language` set to "Russian"
   **When** the install command is built
   **Then** `--communication-language Russian` is used

7. **Given** the user has no `preferred_agent_language`
   **When** the install command is built
   **Then** `--communication-language English` is used as fallback

## Tasks / Subtasks

- [ ] Task 1: Create `BmadMethodInjector` service (AC: #1–#7)
  - [ ] Create `app/services/bmad_method_injector.rb`
  - [ ] Define `AGENT_TYPE_TO_BMAD_TOOL` constant mapping
  - [ ] Implement `initialize(container_id, session, runtime:)`
  - [ ] Implement `inject!` — orchestrator calling `run_bmad_install` then `hide_bmad_in_vscode` (Story 33.3)
  - [ ] Implement `run_bmad_install` — builds and executes npx command
  - [ ] Implement `resolve_modules` — reads from session.bmad_modules
  - [ ] Implement `resolve_language` — user.preferred_agent_language || "English"
  - [ ] Implement `resolve_tool` — maps agent_type via constant
- [ ] Task 2: Write unit tests (AC: #1–#7)
  - [ ] Test command generation for each agent_type
  - [ ] Test modules flag with default and custom modules
  - [ ] Test language resolution with and without user preference
  - [ ] Test `inject!` calls runtime.exec with correct command array
  - [ ] Mock `runtime.exec` — use `stub_support.rb` patterns

## Dev Notes

- **Runtime exec pattern:** `runtime.exec(container_id, cmd)` returns `[stdout, stderr, exit_code]`
  - Docker: `[[stdout_lines], [stderr_lines], exit_code]`
  - K8s: `[stdout, stderr, exit_code]`
  - See `BaseStrategy#read_file_from_container` for pattern
- **User display_name:** `session.user.display_name` or fallback to `session.user.email`
- **Depends on Story 33.1:** Uses `session.bmad_modules` helper
- `hide_bmad_in_vscode` is a separate method but called within `inject!` — Story 33.3 adds that implementation
- Keep `hide_bmad_in_vscode` as a no-op stub in this story, implemented in 33.3

### Architecture Compliance

```ruby
AGENT_TYPE_TO_BMAD_TOOL = {
  "cursor_cli" => "cursor",
  "claude_code" => "claude-code",
  "codex" => "codex",
  "gemini_cli" => "gemini"
}.freeze
```

Full command:
```ruby
["npx", "bmad-method", "install",
 "--directory", "/workspace",
 "--modules", modules,
 "--tools", tool,
 "--user-name", user_name,
 "--communication-language", language,
 "--document-output-language", "English",
 "--output-folder", "/workspace/outputs",
 "--yes"]
```

### Project Structure Notes

- File: `app/services/bmad_method_injector.rb` — top-level service, not namespaced
- Pattern follows other injectors/services that interact with containers (e.g., `SessionContextService`)
- Uses `# frozen_string_literal: true` header

### References

- [Source: app/services/container_strategies/base_strategy.rb#L170-175] — runtime.exec pattern
- [Source: app/services/session_context_service.rb#L396-401] — exec in session context
- [Source: ai/bmad-method-checkbox-integration.md#5.3] — PRD BmadMethodInjector spec
- [Source: ai/project-context.md#Container-Runtime] — Docker vs K8s exec differences

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
