# Story 19.11: Update Seeds and Migration

Status: ready-for-dev

## Story

As a developer,
I want all tool seeds updated with `execution_mode` and new tools seeded,
so that the framework is ready after deploy.

## Acceptance Criteria

1. Existing internal tool seeds updated: `list_sub_steps` → `execution_mode: :app`, `mark_sub_step` → `execution_mode: :app`, `write_step_note` → `execution_mode: :app`
2. `code_climate` seed updated: `execution_mode: :container`
3. New tool seed: `read_tool_result` (execution_mode: :app, kind: :internal)
4. `read_tool_result` is NOT `workflow_only` — available in all sessions
5. Migration adds `execution_mode` column to tools with default `"container"` (if not already done in 19.1)
6. All seeds use `find_or_create_by!` (idempotent)

## Tasks / Subtasks

- [ ] Task 1: Update existing seeds (AC: #1, #2, #6)
  - [ ] `db/seeds.rb` — add `execution_mode: :app` to list_sub_steps, mark_sub_step, write_step_note seeds
  - [ ] `db/seeds/code_report.rb` — add `execution_mode: :container` to code_climate seed
  - [ ] Ensure all seeds use `find_or_create_by!` pattern
- [ ] Task 2: New read_tool_result seed (AC: #3, #4, #6)
  - [ ] Add seed for `read_tool_result` tool
  - [ ] Kind: `:internal`, execution_mode: `:app`
  - [ ] workflow_only: `false`
  - [ ] Description referencing async tool execution pattern
  - [ ] Input schema: `{ tool_result_id: { type: "string" } }` with required field
- [ ] Task 3: Verify migration (AC: #5)
  - [ ] Confirm 19.1 migration adds `execution_mode` column
  - [ ] Confirm 19.2 migration creates `tool_results` table
  - [ ] Verify both can run in sequence without conflicts
- [ ] Task 4: Tests
  - [ ] Test seeds are idempotent (run twice, no errors)
  - [ ] Test all internal tools have correct execution_mode after seeding
  - [ ] Test read_tool_result is not workflow_only

## Dev Notes

- This story is mostly about data — making sure all seeds reflect the new framework
- Can be done in parallel with code stories (19.4-19.6) since it only touches seed files
- `find_or_create_by!` ensures existing deployments are updated on next seed run

### Project Structure Notes

- `db/seeds.rb` — modify existing
- `db/seeds/code_report.rb` — modify existing

### References

- [Source: ai/epics/epic-19-tool-execution-framework.md#Story-19.11] — acceptance criteria
- [Source: ai/epics/epic-19-tool-execution-framework.md#Story-19.8] — read_tool_result seed example
- [Source: db/seeds.rb] — current seed structure
