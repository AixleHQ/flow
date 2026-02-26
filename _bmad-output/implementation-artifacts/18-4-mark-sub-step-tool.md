# Story 18.4: mark_sub_step Tool

Status: review

## Story

As an agent running a workflow step,
I want to update a sub-step's status with notes and structured data,
so that progress is tracked and decisions flow to subsequent steps.

## Acceptance Criteria

1. Handler `InternalTools::MarkSubStep` accepts `id`, `status`, `note`, `data`
2. `id` (required) — SubStepRun ID, `status` (required) — one of `in_progress`, `completed`, `skipped`
3. `note` (optional string) — what was done, decisions made
4. `data` (optional object) — structured findings, metrics, decisions
5. Sets `started_at` when status changes to `in_progress`
6. Sets `completed_at` when status changes to `completed` or `skipped`
7. Returns updated sub-step run as JSON
8. Returns error if sub-step run not found or not in current step
9. Returns error if called outside workflow context

## Tasks / Subtasks

- [x] Task 1: Create handler (AC: #1–#7)
  - [x] Create `app/services/internal_tools/mark_sub_step.rb`
  - [x] Find SubStepRun by `id` scoped to current `step_run`
  - [x] Update `status`, `note`, `data` fields
  - [x] Set timestamps based on status transition
  - [x] Return updated record as JSON
- [x] Task 2: Guards (AC: #8, #9)
  - [x] `require_workflow_context!`
  - [x] Scope find to `step_run.sub_step_runs` — returns error if not found
- [x] Task 3: Tests (AC: all)
  - [x] Test status transitions with correct timestamps
  - [x] Test note and data persistence
  - [x] Test scoping — can't update sub-step from another step
  - [x] Test error on missing sub-step run

## Dev Notes

### Handler Implementation

```ruby
module InternalTools
  class MarkSubStep < Base
    def execute
      require_workflow_context!
      ssr = step_run.sub_step_runs.find_by(id: params[:id])
      return error("Sub-step run #{params[:id]} not found in current step") unless ssr

      ssr.status = params[:status]
      ssr.note = params[:note] if params[:note].present?
      ssr.data = params[:data] if params[:data].present?
      ssr.started_at = Time.current if params[:status] == "in_progress" && ssr.started_at.nil?
      ssr.completed_at = Time.current if %w[completed skipped].include?(params[:status])
      ssr.save!

      success({ id: ssr.id, status: ssr.status, note: ssr.note, data: ssr.data }.to_json)
    end
  end
end
```

### References

- [Source: ai/workflow-architecture.md#Section 6.2] — mark_sub_step spec
- [Source: ai/epics/epic-18-internal-tools.md#Story 18.4]

## Dev Agent Record

### Agent Model Used
claude-4.6-opus-high

### Completion Notes List
- Handler validates status against allowed list, scopes find to step_run.sub_step_runs
- Sets started_at on in_progress, completed_at on completed/skipped
- 7 tests: transitions, note/data, scoping, invalid status, missing SSR, workflow guard

### File List
- app/services/internal_tools/mark_sub_step.rb (new)
- test/services/internal_tools/mark_sub_step_test.rb (new)
