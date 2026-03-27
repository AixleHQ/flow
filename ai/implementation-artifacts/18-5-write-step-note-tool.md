# Story 18.5: write_step_note Tool

Status: review

## Story

As an agent running a workflow step,
I want to save a note visible to agents in subsequent steps,
so that context and decisions are passed forward through the workflow.

## Acceptance Criteria

1. Handler `InternalTools::WriteStepNote` accepts `note` (required string)
2. Appends to `StepRun#step_note` (not replaces — multiple calls accumulate)
3. Separator between notes: newline + `---` + newline
4. Returns confirmation with current full note text
5. Returns error if called outside workflow context

## Tasks / Subtasks

- [x] Task 1: Create handler (AC: #1–#4)
  - [x] Create `app/services/internal_tools/write_step_note.rb`
  - [x] Append `params[:note]` to `step_run.step_note`
  - [x] Use separator for readability
  - [x] Return full accumulated note
- [x] Task 2: Workflow guard (AC: #5)
  - [x] Call `require_workflow_context!`
- [x] Task 3: Tests (AC: all)
  - [x] Test first note write (nil → note)
  - [x] Test append (existing + separator + new)
  - [x] Test error outside workflow

## Dev Notes

### Handler Implementation

```ruby
module InternalTools
  class WriteStepNote < Base
    def execute
      require_workflow_context!
      existing = step_run.step_note
      new_note = if existing.present?
        "#{existing}\n---\n#{params[:note]}"
      else
        params[:note]
      end
      step_run.update!(step_note: new_note)
      success("Note saved. Current note:\n#{new_note}")
    end
  end
end
```

### References

- [Source: ai/workflow-architecture.md#Section 6.3] — write_step_note spec
- [Source: ai/epics/epic-18-internal-tools.md#Story 18.5]

## Dev Agent Record

### Agent Model Used
claude-4.6-opus-high

### Completion Notes List
- Appends notes with --- separator, validates non-blank note
- 4 tests: first write, append, blank note error, workflow guard

### File List
- app/services/internal_tools/write_step_note.rb (new)
- test/services/internal_tools/write_step_note_test.rb (new)
