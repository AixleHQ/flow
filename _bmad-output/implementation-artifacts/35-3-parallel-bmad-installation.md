# Story 35.3: Parallel BMAD Installation

Status: ready-for-dev

## Story

As a **developer**,
I want BMAD installation to run in parallel with other session setup steps,
so that it does not add 10-30 seconds to my session startup time.

## Acceptance Criteria

1. **Given** a session with `bmad_enabled: true`
   **When** `assemble_session_context` runs
   **Then** `BmadMethodInjector#inject!` executes concurrently with other independent steps

2. **Given** BMAD installation takes 15 seconds and other steps take 10 seconds
   **When** both run in parallel
   **Then** total time is approximately 15 seconds (not 25)

3. **Given** BMAD installation runs in parallel
   **When** it completes (success or failure)
   **Then** the result is awaited before the final context file is written (since `ContextBuilders::BmadMethod` needs to check if BMAD files exist)

4. **Given** BMAD parallel execution fails with an exception
   **When** the thread/future is joined
   **Then** the exception is caught (not propagated), and the session proceeds normally

## Tasks / Subtasks

- [ ] Task 1: Launch BMAD as early as possible in assemble_session_context (AC: #1, #2)
  - [ ] Start `BmadMethodInjector#inject!` in a `Thread.new` or `Concurrent::Promises.future` right after credentials (Step 1)
  - [ ] BMAD install has no dependency on config_files, MCP, skills, assets, or repos
  - [ ] Only needs container_id and session — both available at method entry
- [ ] Task 2: Await BMAD thread before context file generation (AC: #3)
  - [ ] Insert `bmad_thread.join` (or `bmad_future.value!`) before Step 5 (inject_context_file)
  - [ ] Context builders run during `inject_context_file` → `BmadMethod` builder needs BMAD files present
- [ ] Task 3: Handle thread exceptions gracefully (AC: #4)
  - [ ] `Thread.new` with internal rescue (Story 35.2 already handles this in `inject!`)
  - [ ] Double-check: join doesn't re-raise since inject! swallows exceptions
- [ ] Task 4: Add timing instrumentation (AC: #2)
  - [ ] Log parallel start time and join time
  - [ ] Compare total assembly time with and without parallelism in dev/staging
- [ ] Task 5: Write tests (AC: #1–#4)
  - [ ] Test: BMAD runs while other steps execute (assert overlap via timing)
  - [ ] Test: context file is written after BMAD completes
  - [ ] Test: BMAD failure in thread doesn't crash assembly

## Dev Notes

### Current Sequential Flow

```ruby
# app/services/session_context_service.rb lines 74-121
def assemble_session_context(container_id, session, credential: nil)
  # Step 1: Credentials
  # Step 2: Config files
  # Step 3: MCP config
  # Step 4: Skills
  # Step 5: Context file (ContextBuilders run here — including BmadMethod)
  # Step 6: Assets
  # Step 7: Repositories
  # Step 8: Context log
end
```

All steps currently run sequentially. No threading or concurrency.

### Proposed Parallel Flow

```ruby
def assemble_session_context(container_id, session, credential: nil)
  context_log = ContextLog.new(session)
  
  # Launch BMAD early — no dependencies on other steps
  bmad_thread = nil
  if SessionConfigResolver.new(session).resolve_bmad_enabled
    bmad_thread = Thread.new do
      measure_step("bmad_method") do
        BmadMethodInjector.new(container_id, session, runtime: runtime).inject!
      end
    end
  end

  # Step 1: Credentials (sequential)
  # Step 2: Config files (sequential)
  # Step 3: MCP config (sequential)
  # Step 4: Skills (sequential)

  # Await BMAD before context file — builders need BMAD files
  if bmad_thread
    measure_step("bmad_method_join") { bmad_thread.join }
  end

  # Step 5: Context file (ContextBuilders::BmadMethod checks filesystem)
  # Step 6: Assets
  # Step 7: Repositories
  # Step 8: Context log
end
```

### Why Thread.new vs Concurrent::Promises

The project doesn't currently use `concurrent-ruby` gem in the session context path. `Thread.new` + `join` is simpler and consistent with the codebase style. If `concurrent-ruby` is already in the Gemfile (check), `Concurrent::Promises.future` is also fine.

### Thread Safety Considerations

- `BmadMethodInjector` uses `runtime.exec` — container operations are process-level (Docker API calls), safe from different threads
- `measure_step` uses `Process.clock_gettime` — thread-safe
- `Rails.logger` is thread-safe
- No shared mutable state between BMAD thread and main thread

### Timing Impact

- BMAD install typically takes 10-30s (npm install + file writes)
- Steps 1-4 typically take 5-15s combined
- Parallelism saves ~5-15s per session startup

### References

- [Source: app/services/session_context_service.rb#L74-121] — assemble_session_context
- [Source: app/services/container_strategies/tool_strategy.rb#L44-56] — timeout pattern for reference
- [Source: ai/epics/epic-35-bmad-container-hardening.md#Story-35.3] — story spec

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
