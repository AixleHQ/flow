# Story 33.1: Data Model — bmad_enabled in session_config

Status: ready-for-dev

## Story

As a **platform developer**,
I want `bmad_enabled` and `bmad_modules` stored in the existing `session_config` JSONB on `terminal_sessions`,
so that the system knows whether BMAD should be installed for a given session without requiring a new migration.

## Acceptance Criteria

1. **Given** a standalone session is created with `bmad_enabled: true` in session_config
   **When** the session record is persisted
   **Then** `session.session_config["bmad_enabled"]` returns `true`
   **And** `session.session_config["bmad_modules"]` defaults to `["bmm"]` if not explicitly provided

2. **Given** a standalone session is created without BMAD configuration
   **When** the session record is persisted
   **Then** `session.session_config["bmad_enabled"]` returns `nil` or `false`

3. **Given** the user specifies custom modules `["bmm", "cis", "bmb"]`
   **When** the session is created
   **Then** `session.session_config["bmad_modules"]` stores the exact array provided

4. **Given** the `bmad_enabled?` helper is called on a session with `bmad_enabled: true`
   **When** the method returns
   **Then** it returns `true`

5. **Given** the API receives `session_config: { bmad_enabled: true }` in the create payload
   **When** strong params are processed
   **Then** `bmad_enabled` is permitted and stored in session_config JSONB

## Tasks / Subtasks

- [ ] Task 1: Add `bmad_enabled?` helper to TerminalSession model (AC: #1, #4)
  - [ ] Add `BMAD_DEFAULT_MODULES = %w[bmm].freeze` constant
  - [ ] Add `bmad_enabled?` method: `session_config&.dig("bmad_enabled") == true`
  - [ ] Add `bmad_modules` method: `session_config&.dig("bmad_modules") || BMAD_DEFAULT_MODULES`
- [ ] Task 2: Update controller strong params to permit BMAD keys (AC: #5)
  - [ ] In `TerminalSessionsController`, update `session_config` permit to include `bmad_enabled` and `bmad_modules`
  - [ ] Current code: `raw.to_unsafe_h.slice("config_files", "env_vars")` → add `"bmad_enabled", "bmad_modules"`
- [ ] Task 3: Write unit tests (AC: #1–#5)
  - [ ] Test `bmad_enabled?` returns true/false correctly
  - [ ] Test `bmad_modules` returns default when not specified
  - [ ] Test `bmad_modules` returns custom array when specified
  - [ ] Test controller permits `bmad_enabled` in session_config

## Dev Notes

- **No migration needed** — `session_config` JSONB column already exists on `terminal_sessions` (schema.rb line 582, default `{}`)
- `session_config` currently stores `config_files` and `env_vars` — BMAD keys are additive
- Model file: `app/models/terminal_session.rb`
- Controller file: `app/controllers/api/v1/terminal_sessions_controller.rb` (lines 105–108 for strong params)
- The `agent_type` field validates `in: %w[claude_code cursor_cli codex gemini_cli]` — this is used later in Story 33.2 for BMAD tool flag mapping

### Project Structure Notes

- `session_config` JSONB pattern is already established — no architectural deviation
- Helper methods follow existing patterns: `config_files`, `env_vars` are already defined on TerminalSession

### References

- [Source: app/models/terminal_session.rb] — existing session_config helpers
- [Source: app/controllers/api/v1/terminal_sessions_controller.rb#L105-108] — strong params
- [Source: db/schema.rb#L582] — session_config column definition
- [Source: ai/epics/epic-33-bmad-standalone-session.md#Story-33.1] — story spec
- [Source: ai/bmad-method-checkbox-integration.md#5.1] — PRD migration section

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
