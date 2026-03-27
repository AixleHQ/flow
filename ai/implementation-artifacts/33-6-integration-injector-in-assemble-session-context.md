# Story 33.6: Integration — BmadMethodInjector in assemble_session_context

Status: ready-for-dev

## Story

As a **developer enabling BMAD**,
I want the BMAD installation to happen automatically during session context assembly,
so that when my session starts, BMAD is already set up and ready to use.

## Acceptance Criteria

1. **Given** a session with `bmad_enabled: true`
   **When** `SessionContextService#assemble_session_context` runs
   **Then** `BmadMethodInjector#inject!` is called after repositories (step 7) and before context_log (step 8)
   **And** the step is measured via `measure_step("bmad_method")`

2. **Given** a session with `bmad_enabled: false`
   **When** `SessionContextService#assemble_session_context` runs
   **Then** `BmadMethodInjector` is NOT called

3. **Given** BMAD installation completes successfully
   **When** the session context file is generated
   **Then** `ContextBuilders::BmadMethod` generates the `<bmad-method>` context section

4. **Given** BMAD outputs are produced during the session
   **When** the session ends
   **Then** existing `collect_outputs` picks up files from `/workspace/outputs/` including BMAD artifacts

## Tasks / Subtasks

- [ ] Task 1: Add BMAD injection step to `assemble_session_context` (AC: #1, #2)
  - [ ] In `SessionContextService#assemble_session_context`, add step 7.5 between repositories and context_log
  - [ ] Guard with `SessionConfigResolver.new(session).resolve_bmad_enabled`
  - [ ] Instantiate `BmadMethodInjector.new(container_id, session, runtime: runtime)`
  - [ ] Call `injector.inject!` inside `measure_step("bmad_method")`
- [ ] Task 2: Write integration test (AC: #1–#4)
  - [ ] Test BMAD step runs when bmad_enabled is true
  - [ ] Test BMAD step is skipped when bmad_enabled is false
  - [ ] Test measure_step records timing
  - [ ] Mock runtime.exec to verify correct command is sent

## Dev Notes

- **File:** `app/services/session_context_service.rb`
- **Current step order (lines 74–119):**
  1. credentials
  2. config_files
  3. mcp_config
  4. skills
  5. context_file ← NOTE: context_file is step 5, not after step 7!
  6. assets
  7. repositories
  8. context_log

- **IMPORTANT:** The context_file (step 5) is generated BEFORE repositories (step 7). Since `ContextBuilders::BmadMethod` needs BMAD files to exist, and BMAD install happens at step 7.5, the builder's `applicable?` should check the resolver (not filesystem). The builder injects BMAD info regardless of install timing — it trusts that the install will have run by the time the agent reads the context file.

- **Alternative approach:** Move BMAD install to step 4.5 (before context_file generation) so the builder can optionally verify filesystem. But since the builder uses `resolve_bmad_enabled` (config-based, not filesystem-based), step 7.5 is fine.

- **Runtime access:** `SessionContextService` already has `@runtime` and `container_id` available.

### Integration Code

```ruby
# Step 7.5: BMAD Method
if SessionConfigResolver.new(session).resolve_bmad_enabled
  measure_step("bmad_method") do
    BmadMethodInjector.new(container_id, session, runtime: runtime).inject!
  end
end
```

### Project Structure Notes

- `SessionContextService` already follows the `measure_step` pattern for all steps
- `runtime` is available as `@runtime` in the service
- `container_id` is the first parameter of `assemble_session_context`

### References

- [Source: app/services/session_context_service.rb#L74-119] — assemble_session_context steps
- [Source: ai/bmad-method-checkbox-integration.md#5.4] — PRD integration spec
- [Source: ai/epics/epic-33-bmad-standalone-session.md#Story-33.6] — story spec

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
