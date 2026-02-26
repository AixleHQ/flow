# Story 18.3: list_sub_steps Tool

Status: review

## Story

As an agent running a workflow step,
I want to list current sub-steps with their statuses,
so that I can track progress and know what to work on next.

## Acceptance Criteria

1. Handler `InternalTools::ListSubSteps` returns JSON array of sub-step runs for current step
2. Each entry contains: `id`, `position`, `name`, `description`, `status`, `note`, `data`
3. Status values: `pending`, `in_progress`, `completed`, `skipped`
4. Returns error if called outside workflow context (no step_run)
5. No input parameters required
6. Results ordered by sub-step position

## Tasks / Subtasks

- [x] Task 1: Create handler (AC: #1, #2, #3, #6)
  - [x] Create `app/services/internal_tools/list_sub_steps.rb`
  - [x] Query `step_run.sub_step_runs.includes(:sub_step).order('sub_steps.position')`
  - [x] Map to JSON array with required fields
  - [x] Return via `success(json_array.to_json)`
- [x] Task 2: Workflow guard (AC: #4)
  - [x] Call `require_workflow_context!` at start of `execute`
- [x] Task 3: Tests (AC: all)
  - [x] Test returns sub-step runs with correct fields
  - [x] Test ordering by position
  - [x] Test error when no step_run

## Dev Notes

### Handler Implementation

```ruby
module InternalTools
  class ListSubSteps < Base
    def execute
      require_workflow_context!
      sub_step_runs = step_run.sub_step_runs
        .includes(:sub_step)
        .order("sub_steps.position")
      result = sub_step_runs.map do |ssr|
        {
          id: ssr.id,
          position: ssr.sub_step.position,
          name: ssr.sub_step.name,
          description: ssr.sub_step.description,
          status: ssr.status,
          note: ssr.note,
          data: ssr.data
        }
      end
      success(result.to_json)
    end
  end
end
```

### Dependencies

- Requires `StepRun` and `SubStepRun` models (Epic 12)
- Requires `TerminalSession#step_run` association

### References

- [Source: ai/workflow-architecture.md#Section 6.1] — list_sub_steps spec
- [Source: ai/epics/epic-18-internal-tools.md#Story 18.3]

## Dev Agent Record

### Agent Model Used
claude-4.6-opus-high

### Completion Notes List
- Handler queries step_run.sub_step_runs with eager-loaded sub_step, orders by position
- Returns JSON array with id, position, name, description, status, note, data
- 3 tests pass

### File List
- app/services/internal_tools/list_sub_steps.rb (new)
- test/services/internal_tools/list_sub_steps_test.rb (new)
