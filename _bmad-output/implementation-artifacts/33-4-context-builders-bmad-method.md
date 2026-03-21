# Story 33.4: ContextBuilders::BmadMethod

Status: ready-for-dev

## Story

As an **AI agent in a BMAD-enabled session**,
I want a context section informing me about BMAD availability, config location, and output rules,
so that I can use BMAD slash-commands and produce artifacts in the correct location.

## Acceptance Criteria

1. **Given** a session with `bmad_enabled: true`
   **When** `SessionContextConstructor` builds the context
   **Then** a `<bmad-method>` section is included with priority `:info` and position_hint `:middle`

2. **Given** the BmadMethod builder is active
   **When** the context section is rendered
   **Then** it contains references to BMAD files (`/workspace/_bmad/`), config (`/workspace/_bmad/core/config.yaml`), output folder (`/workspace/outputs/`), and instructions to use available skills/commands

3. **Given** a session with `bmad_enabled: false` or nil
   **When** `SessionContextConstructor` builds the context
   **Then** no `<bmad-method>` section is included (`applicable?` returns `false`)

4. **Given** the context is rendered to XML-markdown
   **When** the output is inspected
   **Then** it contains `<bmad-method priority="info">` with proper opening/closing tags

## Tasks / Subtasks

- [ ] Task 1: Create `ContextBuilders::BmadMethod` (AC: #1–#4)
  - [ ] Create `app/services/context_builders/bmad_method.rb`
  - [ ] Inherit from `ContextBuilders::Base`
  - [ ] Implement `applicable?` — `SessionConfigResolver.new(session).resolve_bmad_enabled`
  - [ ] Implement `build` — return `[section(tag: "bmad-method", priority: :info, content: build_bmad_context)]`
  - [ ] Implement `build_bmad_context` — heredoc with BMAD info
- [ ] Task 2: Register in SessionContextConstructor (AC: #1)
  - [ ] Add `ContextBuilders::BmadMethod` to BUILDERS array after `Resources`, before `OutputRules`
- [ ] Task 3: Write unit tests (AC: #1–#4)
  - [ ] Test `applicable?` returns false for non-BMAD sessions
  - [ ] Test `applicable?` returns true for BMAD-enabled sessions
  - [ ] Test `build` returns section with correct tag and priority
  - [ ] Test content includes all required references
  - [ ] Integration test: full constructor output includes `<bmad-method` for BMAD session

## Dev Notes

- **Follow existing pattern exactly:** See `app/services/context_builders/board_context.rb` (76 lines) as reference
- **Builder interface from Base:**
  - `applicable?` — return boolean
  - `build` — return `Array<ContextSection>`
  - `section(tag:, priority:, content:, position_hint:)` — convenience helper
- **BUILDERS array location:** `app/services/session_context_constructor.rb` lines 4–14
  - Insert between `ContextBuilders::Resources` and `ContextBuilders::OutputRules`
- **Context content:**
  ```markdown
  ## BMAD Method

  The BMAD Method is installed and available in this session.
  You have access to slash-commands for structured development workflows.

  - BMAD files: `/workspace/_bmad/`
  - BMAD config: `/workspace/_bmad/core/config.yaml`
  - Output folder: `/workspace/outputs/`

  Use the available skills/commands to invoke BMAD workflows.
  All BMAD output must go to `/workspace/outputs/`.
  ```
- **SessionConfigResolver dependency:** Story 33.5 adds `resolve_bmad_enabled` — if implementing in parallel, can use `session.bmad_enabled?` directly as interim

### Project Structure Notes

- File: `app/services/context_builders/bmad_method.rb`
- Follows `module ContextBuilders` namespace — consistent with all other builders
- `# frozen_string_literal: true` header required

### References

- [Source: app/services/context_builders/base.rb] — builder interface (54 lines)
- [Source: app/services/context_builders/board_context.rb] — example builder pattern
- [Source: app/services/session_context_constructor.rb#L4-14] — BUILDERS array
- [Source: ai/session-context-constructor.md#5.5] — BmadMethod builder design spec
- [Source: ai/bmad-method-checkbox-integration.md#5.5] — PRD builder spec

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
