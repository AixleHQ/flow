# Story 19.10: ToolResult Cleanup Job

Status: ready-for-dev

## Story

As a platform operator,
I want old tool results automatically cleaned up,
so that S3 storage doesn't grow unbounded.

## Acceptance Criteria

1. `ToolResultCleanupJob < ApplicationJob` created
2. Retention period configurable via `Settings.tool_results.retention_days` (default: 30)
3. Finds `completed` and `failed` ToolResults older than retention period (using `stale` scope from 19.2)
4. Deletes Shrine attachments (stdout, stderr, result_data, output) from S3
5. Sets state to `expired`, nulls all `*_data` columns
6. Record itself preserved for audit trail (execution_id, exit_code, error, duration_ms remain)
7. Job registered in Temporal schedules (daily)
8. `processing` results older than 24h are logged as warning but NOT expired

## Tasks / Subtasks

- [ ] Task 1: Cleanup Job (AC: #1-#6)
  - [ ] Create `app/jobs/tool_result_cleanup_job.rb`
  - [ ] Retention constant using `Settings.tool_results&.retention_days || 30`
  - [ ] Find stale records via `ToolResult.stale(retention_period)`
  - [ ] For each record: delete all 4 Shrine attachments from S3
  - [ ] Update record: state → expired, all `*_data` columns → nil
  - [ ] Preserve metadata columns for audit
- [ ] Task 2: Stuck execution warning (AC: #8)
  - [ ] Find `processing` ToolResults older than 24 hours
  - [ ] Log warning with execution_ids
  - [ ] Do NOT expire them (may be legitimately long-running or need manual investigation)
- [ ] Task 3: Settings (AC: #2)
  - [ ] Add `tool_results.retention_days: 30` to Settings defaults (config/settings.yml or equivalent)
- [ ] Task 4: Temporal schedule (AC: #7)
  - [ ] Register daily schedule for `ToolResultCleanupJob`
  - [ ] Follow existing Temporal schedule registration pattern
- [ ] Task 5: Tests
  - [ ] Test cleanup expires old completed results
  - [ ] Test cleanup expires old failed results
  - [ ] Test cleanup preserves recent results
  - [ ] Test cleanup preserves processing results (even old ones)
  - [ ] Test Shrine attachments are deleted from storage
  - [ ] Test audit columns preserved after expiry
  - [ ] Test configurable retention period

## Dev Notes

- No `expires_at` column on the model — retention is global and based on `created_at`
- Cleaning up in batches with `find_each` to avoid loading all records into memory
- Shrine's `destroy` method on attachments handles S3 deletion
- Consider running cleanup in batches if volume is large (future concern)

### Project Structure Notes

- `app/jobs/tool_result_cleanup_job.rb` — new file

### References

- [Source: ai/tool-execution-framework.md#3.5] — cleanup job code
- [Source: ai/epics/epic-19-tool-execution-framework.md#Story-19.10] — acceptance criteria
