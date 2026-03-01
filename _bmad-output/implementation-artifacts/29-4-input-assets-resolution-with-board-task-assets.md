# Story 29.4: Input Assets Resolution with Board Task Assets

Status: done

## Story

As a system,
I want input assets to be additively merged from Workflow base assets + WorkflowRun user inputs + BoardTask assets,
So that board task attachments automatically become available in the session alongside other configured assets.

## Acceptance Criteria

1. **Full additive merge** — Given a Workflow with `config["base_asset_ids"] = [100]`, WorkflowRun with `input_asset_ids = [101]`, and BoardTask with task_assets pointing to asset_ids `[102, 103]`, when resolver resolves input_asset_ids, then result is `[100, 101, 102, 103]` (union, deduplicated)

2. **No board task** — Given a workflow session without board_task, when resolver resolves input_asset_ids, then result is `[100, 101]` (workflow base + run user)

3. **Standalone pass-through** — Given a standalone session with `input_asset_ids = [200]`, when resolver resolves, then result is `[200]`

4. **Empty sources** — Given a workflow with no base_asset_ids and a workflow_run with no input_asset_ids, when board_task has assets `[102]`, then result is `[102]`

5. **Workflow helper** — Workflow model exposes `base_asset_ids` reading from `config` jsonb, returning `[]` when absent

6. **Board task asset extraction** — Board task assets are resolved via existing `board_task.task_assets` association, extracting `asset_id` from each

## Tasks / Subtasks

- [ ] Task 1: Add Workflow helper method (AC: #5)
  - [ ] Add `base_asset_ids` method: `config&.dig("base_asset_ids") || []`
- [ ] Task 2: Implement input_asset resolution (AC: #1, #2, #3, #4)
  - [ ] Workflow sessions: merge `workflow.base_asset_ids + workflow_run.input_asset_ids + board_task_asset_ids`
  - [ ] Standalone sessions: pass-through `session.input_assets.pluck(:id)`
  - [ ] Handle nil board_task gracefully (return empty)
- [ ] Task 3: Implement board_task_asset_ids helper (AC: #6)
  - [ ] `board_task&.task_assets&.pluck(:asset_id) || []`
  - [ ] Return `[]` when board_task is nil
- [ ] Task 4: Write tests (AC: #1-#6)
  - [ ] Test full merge: workflow base + run + board task
  - [ ] Test without board_task
  - [ ] Test standalone pass-through
  - [ ] Test all sources empty
  - [ ] Test deduplication when same asset appears in multiple sources

## Dev Notes

### Architecture Patterns

- **Three sources for input_assets** — unlike tools/skills/mcp which have 2-3 sources, input_assets have 3: workflow base, run-level user selection, and board task attachments
- **WorkflowRun.input_asset_ids** — this is likely a postgres array column or derived from a join table (check actual implementation: `workflow_run.input_asset_ids` or `workflow_run.input_assets.pluck(:id)`)
- **BoardTask.task_assets** — `has_many :task_assets` from Epic 21 (Story 21.6). Each TaskAsset `belongs_to :asset`

### Existing Code Context

- `WorkflowRun` model — `input_asset_ids` available as column or association
- `BoardTask` model — `has_many :task_assets`, each with `asset_id` FK
- `TaskAsset` model — join model between Task and Asset from Epic 21
- `LaunchStepSessionActivity#attach_resources!` — currently only attaches `workflow_run.input_asset_ids`, ignores workflow base and board task assets. This is the gap

### File Locations

- Modified: `app/models/workflow.rb` — add `base_asset_ids` helper
- Modified: `app/services/session_config_resolver.rb` — update `resolve_input_asset_ids`
- Modified: `test/services/session_config_resolver_test.rb` — add test cases

### Testing Standards

- **Framework:** Minitest with FactoryBot
- **Run:** `docker exec app-web-1 bundle exec rails test test/services/session_config_resolver_test.rb`
- Use `:board_task` factory with associated `:task_asset` records

### References

- [Source: ai/session-config-cascade.md#3.6] — Input assets resolution with 3 sources
- [Source: ai/epics/epic-29-session-config-resolver.md#Story 29.4] — AC
- [Source: app/temporal/activities/workflow/launch_step_session_activity.rb#78-82] — Current run-only asset attachment
- [Source: ai/workflow-architecture.md#2.7] — WorkflowRunAsset model

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
