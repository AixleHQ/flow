# Story 33.5: SessionConfigResolver — bmad_enabled Resolution

Status: ready-for-dev

## Story

As a **platform developer**,
I want `SessionConfigResolver` to resolve `bmad_enabled` from the appropriate source,
so that the BMAD integration logic has a single source of truth for whether BMAD should be active.

## Acceptance Criteria

1. **Given** a standalone session with `session_config["bmad_enabled"] = true`
   **When** `SessionConfigResolver.new(session).resolve_bmad_enabled` is called
   **Then** it returns `true`

2. **Given** a standalone session without `bmad_enabled` in session_config
   **When** `resolve_bmad_enabled` is called
   **Then** it returns `false`

3. **Given** a workflow step session where `step.bmad_enabled = true`
   **When** `resolve_bmad_enabled` is called
   **Then** it returns `true`

4. **Given** a workflow step session where `step.bmad_enabled = false`
   **When** `resolve_bmad_enabled` is called
   **Then** it returns `false`

## Tasks / Subtasks

- [ ] Task 1: Add `resolve_bmad_enabled` to SessionConfigResolver (AC: #1–#4)
  - [ ] Add public method `resolve_bmad_enabled`
  - [ ] Standalone path: `session.session_config&.dig("bmad_enabled") == true`
  - [ ] Workflow path: `step&.bmad_enabled || false`
  - [ ] Use existing `standalone_session?` / `workflow_session?` helpers
- [ ] Task 2: Write unit tests (AC: #1–#4)
  - [ ] Test standalone session with bmad_enabled true
  - [ ] Test standalone session without bmad_enabled
  - [ ] Test workflow session with step.bmad_enabled true
  - [ ] Test workflow session with step.bmad_enabled false

## Dev Notes

- **File:** `app/services/session_config_resolver.rb`
- **Existing pattern:** resolver already has `resolve_agent_runtime`, `resolve_mode`, `resolve_tool_ids`, etc.
- **Session type detection:** `standalone_session?` = `!step_run.present?`, `workflow_session?` = `step_run.present?` (lines 58–60)
- **Navigation:** `step_run` → `step_run.step` for workflow step config
- **Note:** The workflow path (`step.bmad_enabled`) depends on Epic 34 (Story 34.1 migration). For now, handle gracefully: `step&.respond_to?(:bmad_enabled) && step.bmad_enabled` or simply `step&.bmad_enabled || false` which returns false if column doesn't exist yet.

### Implementation

```ruby
def resolve_bmad_enabled
  if standalone_session?
    session.session_config&.dig("bmad_enabled") == true
  else
    step&.bmad_enabled || false
  end
end
```

### Project Structure Notes

- Adds one method to existing service — minimal change
- Follows existing `resolve_*` pattern exactly
- The `step` helper is already defined via `step_run&.step` in the resolver

### References

- [Source: app/services/session_config_resolver.rb#L58-70] — session type detection
- [Source: app/services/session_config_resolver.rb] — existing resolve_* methods pattern
- [Source: ai/bmad-method-checkbox-integration.md#5.2] — PRD SessionConfigResolver spec

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
