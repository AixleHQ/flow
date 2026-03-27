# Story 16.2: Collect Logs in before_cleanup

Status: ready-for-dev

## Story

As a platform engineer,
I want `before_cleanup` to create SessionLog records from adapter log paths,
so that logs are persisted as downloadable files before the container is destroyed.

## Acceptance Criteria

1. **AC1: collect_logs method** — New private `collect_logs(container, session, agent_service)` method in `AgentSessionStrategy`. For each path from `adapter.session_log_paths`, reads content from container, creates `SessionLog` record with Shrine file attachment.

2. **AC2: Remove persist_artifacts_to_session** — Delete the `persist_artifacts_to_session` method. Stop writing truncated content to `metadata["artifacts"]`.

3. **AC3: Refactored before_cleanup** — `before_cleanup` calls three private methods in order: `collect_logs` → `collect_outputs` (stub for Story 16.4) → `collect_usage`. Each is independently error-handled.

4. **AC4: Error isolation** — Individual log collection failures don't block other logs or the cleanup process. Each file wrapped in rescue.

5. **AC5: Context result** — `context[:result][:logs_count]` set with number of collected logs.

## Tasks / Subtasks

- [ ] Task 1: Extract `collect_usage` from `before_cleanup` (AC: #3)
  - [ ] 1.1 Create private `collect_usage(session, agent_service, artifacts_hash)` method
  - [ ] 1.2 Move usage collection logic from `before_cleanup` into it
- [ ] Task 2: Create `collect_logs` method (AC: #1, #4)
  - [ ] 2.1 Create private `collect_logs(container, session, agent_service)` method
  - [ ] 2.2 Iterate `agent_service.adapter.session_log_paths`
  - [ ] 2.3 For each path: `read_file_from_container`, skip if blank
  - [ ] 2.4 Create `StringIO` with content, set original filename
  - [ ] 2.5 Create `SessionLog.create!(terminal_session: session, name: basename, file: io)`
  - [ ] 2.6 Return count of collected logs
  - [ ] 2.7 Wrap each file in `rescue StandardError` — log warning, continue
- [ ] Task 3: Add stub `collect_outputs` (AC: #3)
  - [ ] 3.1 Create empty private `collect_outputs(container, session)` returning 0
  - [ ] 3.2 Add TODO comment referencing Story 16.4
- [ ] Task 4: Refactor `before_cleanup` (AC: #3, #5)
  - [ ] 4.1 Replace current body with calls to `collect_logs`, `collect_outputs`, `collect_usage`
  - [ ] 4.2 Set `context[:result][:logs_count]`
  - [ ] 4.3 Set `context[:result][:outputs_count]` (0 for now)
- [ ] Task 5: Remove `persist_artifacts_to_session` (AC: #2)
  - [ ] 5.1 Delete the method
  - [ ] 5.2 Remove `artifacts` hash variable from `before_cleanup`
  - [ ] 5.3 Keep `context[:result][:artifacts_paths]` for backward compat (logs paths)
- [ ] Task 6: Update tests (AC: #1, #2, #3, #4)
  - [ ] 6.1 Update `before_cleanup` tests to expect `SessionLog.create!` calls
  - [ ] 6.2 Test error isolation: one file fails, others still collected
  - [ ] 6.3 Remove tests for `persist_artifacts_to_session`

## Dev Notes

### Current before_cleanup (lines 95-156 of agent_session_strategy.rb)

The current method collects everything into an `artifacts` hash and calls `persist_artifacts_to_session` which truncates content to 500KB and stores in session metadata. This is being replaced.

### New collect_logs Implementation

```ruby
def collect_logs(container, session, agent_service)
  return 0 unless agent_service.adapter.respond_to?(:session_log_paths)

  count = 0
  agent_service.adapter.session_log_paths.each do |path|
    content = read_file_from_container(container, path)
    next if content.blank?

    filename = File.basename(path)
    io = StringIO.new(content)
    io.define_singleton_method(:original_filename) { filename }

    SessionLog.create!(
      terminal_session: session,
      name: filename,
      file: io,
      file_size: content.bytesize,
      content_type: Marcel::MimeType.for(name: filename, extension: File.extname(filename))
    )
    count += 1
    Rails.logger.info("[AgentSession] Collected log: #{path} (#{content.bytesize} bytes)")
  rescue StandardError => e
    Rails.logger.warn("[AgentSession] Failed to collect log #{path}: #{e.message}")
  end
  count
end
```

### New before_cleanup Structure

```ruby
def before_cleanup(context)
  container = context[:container]
  session = TerminalSession.find(input[:session_id])
  agent_service = AgentCredentialsService.for(input[:agent_type])

  logs_count = collect_logs(container, session, agent_service)
  outputs_count = collect_outputs(container, session)
  collect_usage(session, agent_service, container)

  context[:result] ||= {}
  context[:result][:logs_count] = logs_count
  context[:result][:outputs_count] = outputs_count
  Rails.logger.info("[AgentSession] Cleanup: #{logs_count} logs, #{outputs_count} outputs")
end
```

### collect_usage Extraction

Current usage collection logic (lines 125-139 of agent_session_strategy.rb) moves to:

```ruby
def collect_usage(session, agent_service, container)
  return unless agent_service.adapter.respond_to?(:collect_usage)

  agent_service.adapter.collect_usage(session, {})
  Rails.logger.info("[AgentSession] Usage statistics collected for session #{session.id}")
rescue StandardError => e
  Rails.logger.error("[AgentSession] Failed to collect usage: #{e.message}")
end
```

Note: previously `artifacts` hash was passed to `collect_usage` — some adapters read log content from it. Now pass empty hash. Check adapter implementations (`claude_code_adapter`, etc.) — if they read from artifacts hash, they need updating to read from `session.session_logs` instead or accept empty hash gracefully.

### StringIO Filename for Shrine

Shrine needs `original_filename` on the IO object to determine the storage location. `StringIO` doesn't have it by default, so we define it via singleton method. This is a standard Shrine pattern.

### read_file_from_container

Uses `runtime.exec(container, ["cat", path])` — works on running containers. For stopped containers (e.g., stale cleanup), `runtime.read_file(id, path)` uses Docker archive API. In `before_cleanup`, container is still running, so `cat` via exec is fine.

### StaleSessionCleanupActivity Impact

`CleanupStaleSessionsActivity#full_cleanup` calls `strategy.before_cleanup(context)`. After this change, it will create `SessionLog` records for stale sessions too. This is correct — logs should be preserved even for stale sessions.

### Files to Touch

- `web/app/services/container_strategies/agent_session_strategy.rb` — refactor `before_cleanup`, add `collect_logs`, `collect_outputs` (stub), `collect_usage`, remove `persist_artifacts_to_session`
- `web/test/services/container_strategies/agent_session_strategy_test.rb` — update tests

### Dependencies

- **Requires Story 16.1** — `SessionLog` model and uploader must exist

### What NOT To Change

- Do NOT implement `collect_outputs` — that's Story 16.4
- Do NOT modify adapter classes (`claude_code_adapter`, etc.)
- Do NOT change `list_files_in_container` or `read_file_from_container`

### References

- [Source: ai/epics/epic-16-session-outputs-and-config-normalization.md#Story 16.2]
- [Source: web/app/services/container_strategies/agent_session_strategy.rb — before_cleanup lines 95-156]
- [Source: web/app/services/container_strategies/agent_session_strategy.rb — persist_artifacts_to_session lines 162-174]
- [Source: web/app/services/container_strategies/base_strategy.rb — read_file_from_container lines 275-287]
- [Source: web/test/services/container_strategies/agent_session_strategy_test.rb — before_cleanup tests]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
