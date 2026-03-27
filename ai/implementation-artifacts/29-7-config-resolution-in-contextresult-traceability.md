# Story 29.7: Config Resolution in ContextResult Traceability

Status: done

## Story

As a developer,
I want a `config_resolution` section in the ContextResult JSON metadata,
So that I can trace exactly where each resource came from (project inherit, workflow base, step, board task).

## Acceptance Criteria

1. **Workflow session traceability** — Given a workflow session resolved via SessionConfigResolver, when `ContextResult.to_json_hash` is called, then result includes a `config_resolution` key

2. **Agent runtime source tracking** — `config_resolution` includes `agent_runtime` value and `agent_runtime_source` indicating the winning level: `"step_required"`, `"run_override"`, `"user_default"`, `"latest_credential"`, `"fallback"`

3. **Tool breakdown** — `config_resolution.tools` contains: `from_project_inherit_all` (array), `from_workflow_base` (array), `from_step` (array), `resolved` (array — final union)

4. **Input assets breakdown** — `config_resolution.input_assets` contains: `from_workflow_base`, `from_run_user`, `from_board_task`, `resolved`

5. **Standalone traceability** — Given a standalone session, `config_resolution.session_type` is `"standalone"` and all resources show single source `"session_direct"`

6. **Skills and MCP breakdown** — Same pattern as tools: `from_project_inherit_all`, `from_workflow_base`, `from_step`, `resolved`

7. **Stored in terminal_session** — The config_resolution JSON is stored in `terminal_session.context_metadata` alongside existing builder metadata

## Tasks / Subtasks

- [ ] Task 1: Extend SessionConfigResolver to return breakdown (AC: #2, #3, #4, #6)
  - [ ] Add `resolve_with_breakdown` method (or modify `resolve` to include breakdown)
  - [ ] Track which IDs came from which source during resolution
  - [ ] Return `{ resolved: { ... }, breakdown: { ... } }` structure
  - [ ] Agent runtime: track `agent_runtime_source` alongside value
- [ ] Task 2: Add breakdown for each resource type (AC: #3, #4, #6)
  - [ ] Tools: `{ from_project_inherit_all: [], from_workflow_base: [], from_step: [], resolved: [] }`
  - [ ] Skills: same structure
  - [ ] MCP servers: same structure
  - [ ] Input assets: `{ from_workflow_base: [], from_run_user: [], from_board_task: [], resolved: [] }`
  - [ ] Repositories: `{ from_run: [], from_project_fallback: [], resolved: [] }`
- [ ] Task 3: Update ContextResult to include config_resolution (AC: #1, #7)
  - [ ] Add `config_resolution` parameter to ContextResult (optional, Hash)
  - [ ] Include in `to_json_hash` output
  - [ ] Store in `terminal_session.context_metadata` JSONB (column already exists from Epic 25.6)
- [ ] Task 4: Handle standalone (AC: #5)
  - [ ] Standalone breakdown: all resources under single `"session_direct"` source
- [ ] Task 5: Write tests (AC: #1-#7)
  - [ ] Test workflow session breakdown structure
  - [ ] Test agent_runtime_source values for each priority level
  - [ ] Test tool breakdown with inherit_all + base + step
  - [ ] Test input_assets breakdown with board_task
  - [ ] Test standalone shows session_direct

## Dev Notes

### Architecture Patterns

- **Breakdown structure** — the resolver needs to track provenance during resolution, not just return flat arrays. Two approaches:
  1. Separate `resolve` (returns flat config) and `resolve_with_breakdown` (returns config + provenance). Recommended approach — keeps `resolve` simple for LaunchStepSessionActivity
  2. Always return breakdown, flatten in caller
- **ContextResult** already has `to_json_hash` (app/services/context_result.rb, lines 28-42) — extend with `config_resolution` key
- **context_metadata** column on `terminal_sessions` (JSONB) was added in Epic 25 Story 25.6. Currently stores builder metadata

### Resolver Breakdown Return Format

```ruby
{
  session_type: :workflow,
  agent_runtime: "claude_code",
  agent_runtime_source: "user_default",
  tools: {
    from_project_inherit_all: [1, 2, 3],
    from_workflow_base: [4],
    from_step: [5, 6],
    resolved: [1, 2, 3, 4, 5, 6]
  },
  skills: {
    from_project_inherit_all: [],
    from_workflow_base: [10],
    from_step: [11],
    resolved: [10, 11]
  },
  mcp_servers: { ... },
  input_assets: {
    from_workflow_base: [100],
    from_run_user: [101],
    from_board_task: [102, 103],
    resolved: [100, 101, 102, 103]
  },
  repositories: {
    from_run: [1],
    from_project_fallback: [],
    resolved: [1]
  },
  mode: "interactive"
}
```

### Existing Code Context

- `ContextResult#to_json_hash` (app/services/context_result.rb, lines 28-42) — current structure includes `session_id`, `session_type`, `applied_builders`, `sections`
- `terminal_session.context_metadata` — JSONB column, stores `to_json_hash` output from ContextResult (Epic 25.6)
- Integration point: wherever ContextResult is built and stored, include config_resolution from resolver

### Integration Flow

1. `SessionConfigResolver.resolve_with_breakdown(session)` → returns flat config + breakdown
2. `LaunchStepSessionActivity` uses flat config for resource attachment (Story 29.6)
3. `SessionContextConstructor.build_result(session)` creates ContextResult
4. ContextResult receives `config_resolution` breakdown and includes in `to_json_hash`
5. Stored in `terminal_session.update!(context_metadata: result.to_json_hash)`

### File Locations

- Modified: `app/services/session_config_resolver.rb` — add `resolve_with_breakdown`
- Modified: `app/services/context_result.rb` — add `config_resolution` to `to_json_hash`
- Modified: `app/services/session_context_service.rb` — pass breakdown through to ContextResult (if context_metadata storage happens here)
- Modified: `test/services/session_config_resolver_test.rb` — breakdown tests
- Modified: `test/services/context_result_test.rb` — config_resolution in JSON output

### Testing Standards

- **Framework:** Minitest with FactoryBot
- **Run:** `docker exec app-web-1 bundle exec rails test test/services/session_config_resolver_test.rb test/services/context_result_test.rb`
- Test breakdown hash structure for each session type
- Test agent_runtime_source matches the correct priority level

### References

- [Source: ai/session-config-cascade.md#9] — Traceability JSON structure
- [Source: ai/epics/epic-29-session-config-resolver.md#Story 29.7] — AC and technical notes
- [Source: app/services/context_result.rb] — Current ContextResult implementation
- [Source: _bmad-output/implementation-artifacts/25-6-context-traceability-storage-and-api.md] — Context metadata storage

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
