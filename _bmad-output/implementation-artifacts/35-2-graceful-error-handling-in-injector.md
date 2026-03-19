# Story 35.2: Graceful Error Handling in BmadMethodInjector

Status: ready-for-dev

## Story

As a **developer enabling BMAD**,
I want the session to start normally even if BMAD installation fails,
so that a BMAD failure never blocks my work.

## Acceptance Criteria

1. **Given** BMAD installation (`npx bmad-method install`) fails with a non-zero exit code
   **When** the session context assembly continues
   **Then** the error is logged with full command output at `warn` level
   **And** the session proceeds without BMAD

2. **Given** BMAD installation times out (exceeds 60 seconds)
   **When** the timeout is reached
   **Then** the process is killed
   **And** the error is logged
   **And** the session proceeds without BMAD

3. **Given** `npx` is not available in the container (Node.js missing)
   **When** BmadMethodInjector attempts to run the install
   **Then** the error is caught and logged
   **And** the session proceeds without BMAD

4. **Given** a BMAD installation failure occurs
   **When** the session's context_metadata is stored
   **Then** it includes `bmad_install_status: "failed"` and `bmad_install_error: "<message>"` for traceability

5. **Given** `ContextBuilders::BmadMethod` runs after a failed installation
   **When** it checks for BMAD files in the container
   **Then** it returns `applicable? = false` (since BMAD files are absent)
   **And** no `<bmad-method>` section is injected into context

## Tasks / Subtasks

- [ ] Task 1: Implement timeout in BmadMethodInjector#inject! (AC: #2)
  - [ ] Wrap `runtime.exec` call with `Timeout.timeout(60)`
  - [ ] On timeout: log warn, kill exec if possible, proceed
  - [ ] Follow `ToolStrategy` pattern (lines 44–56): `Timeout.timeout` + `rescue Timeout::Error`
- [ ] Task 2: Implement rescue for install failures (AC: #1, #3)
  - [ ] `rescue StandardError => e` around the install execution
  - [ ] Log at `Rails.logger.warn` with structured message: container_id, session_id, exit code, stdout/stderr
  - [ ] Do NOT re-raise — session must proceed
- [ ] Task 3: Record install status in context metadata (AC: #4)
  - [ ] On success: set `bmad_install_status: "success"`
  - [ ] On failure: set `bmad_install_status: "failed"`, `bmad_install_error: e.message`
  - [ ] Store in session.context_metadata or context_log
- [ ] Task 4: Ensure ContextBuilders::BmadMethod handles missing files (AC: #5)
  - [ ] `applicable?` should check for BMAD directory existence in container (not just config flag)
  - [ ] If BMAD files absent → `applicable?` returns false → builder skipped
- [ ] Task 5: Write tests (AC: #1–#5)
  - [ ] Test: install failure → session proceeds, log contains warn
  - [ ] Test: timeout → process killed, session proceeds
  - [ ] Test: npx missing → caught, session proceeds
  - [ ] Test: context_metadata records failure info
  - [ ] Test: builder skips when BMAD files absent

## Dev Notes

### Error Handling Pattern (from codebase)

The project uses a consistent rescue+log+proceed pattern. Closest examples:

**From `session_context_service.rb`** (context_log write failure):
```ruby
rescue => e
  Rails.logger.warn("[SessionContext] Failed to write context log: #{e.message}")
end
```

**From `tool_strategy.rb`** (timeout handling):
```ruby
Timeout.timeout(exec_timeout) do
  wait_result = runtime.wait_container(container, exec_timeout)
end
rescue Timeout::Error
  handle_timeout(container, start_time)
```

**From `base_strategy.rb`** (cleanup with rescue):
```ruby
begin
  runtime.stop_container(container, 5)
rescue StandardError => e
  Rails.logger.warn("[#{strategy_name}] Stop failed: #{e.message}")
end
```

### Proposed inject! Structure

```ruby
def inject!
  Timeout.timeout(INSTALL_TIMEOUT) do
    run_bmad_install
    hide_bmad_in_vscode
  end
  record_status("success")
rescue Timeout::Error => e
  Rails.logger.warn("[BmadMethodInjector] Timeout after #{INSTALL_TIMEOUT}s for session #{session.id}: #{e.message}")
  record_status("failed", "Timeout after #{INSTALL_TIMEOUT}s")
rescue StandardError => e
  Rails.logger.warn("[BmadMethodInjector] Install failed for session #{session.id}: #{e.message}")
  record_status("failed", e.message)
end

INSTALL_TIMEOUT = 60
```

### Context Metadata Storage

Follow the pattern from `context_log.record(:key, data)`:
```ruby
def record_status(status, error = nil)
  context_log.record(:bmad_install, { status: status, error: error }.compact)
end
```

Or attach to session directly if context_log is not accessible from the injector.

### References

- [Source: app/services/session_context_service.rb#L253-256] — rescue+log pattern
- [Source: app/services/container_strategies/tool_strategy.rb#L44-56] — Timeout pattern
- [Source: app/services/container_strategies/base_strategy.rb#L94-98] — rescue+warn+proceed
- [Source: app/services/container_strategies/agent_session_strategy.rb#L139-142] — rescue+log
- [Source: ai/epics/epic-35-bmad-container-hardening.md#Story-35.2] — story spec

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
