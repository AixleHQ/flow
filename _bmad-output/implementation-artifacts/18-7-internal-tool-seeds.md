# Story 18.7: Internal Tool Seeds

Status: review

## Story

As a developer,
I want all internal tools defined in seeds,
so that they are available in development and production environments after deploy.

## Acceptance Criteria

1. `db/seeds.rb` creates all 4 internal tools with correct `input_schema`
2. Idempotent: `find_or_create_by!(name:, kind: :internal)`
3. Tools have clear `description` for MCP discovery by agents
4. Existing `code_climate` seed updated to match final schema
5. Seeds work when run standalone (`rails db:seed`) and are idempotent on re-run

## Tasks / Subtasks

- [x] Task 1: Update existing code_climate seed (AC: #4)
  - [x] Updated description and input_schema (format default: json)
  - [x] Confirmed `kind: :internal`, no scope, no docker_image
- [x] Task 2: Add workflow tools seeds (AC: #1, #2, #3)
  - [x] `list_sub_steps` — no required params, workflow-only description
  - [x] `mark_sub_step` — id + status required, note + data optional
  - [x] `write_step_note` — note required
- [x] Task 3: Organize in seeds.rb (AC: #5)
  - [x] Grouped under "# Internal Tools" section header
  - [x] Placed before company-scoped tools
  - [x] All use `find_or_create_by!(name:, kind: :internal)`
  - [x] Verified idempotency — re-running creates no duplicates

## Dev Notes

### Seed Definitions

```ruby
# ===========================================================================
# Internal Tools (system-provided, no scope)
# ===========================================================================
puts "Creating internal tools..."

Tool.find_or_create_by!(name: "list_sub_steps", kind: :internal) do |t|
  t.display_name = "List Sub-Steps"
  t.description = "List current step's sub-steps with their statuses. Only available during workflow execution."
  t.input_schema = { type: "object", properties: {} }
end

Tool.find_or_create_by!(name: "mark_sub_step", kind: :internal) do |t|
  t.display_name = "Mark Sub-Step"
  t.description = "Update sub-step status with optional note and structured data. Only available during workflow execution."
  t.input_schema = {
    type: "object",
    properties: {
      id: { type: "integer", description: "Sub-step run ID" },
      status: { type: "string", enum: %w[in_progress completed skipped], description: "New status" },
      note: { type: "string", description: "What was done, decisions made" },
      data: { type: "object", description: "Structured data — decisions, metrics, findings" }
    },
    required: %w[id status]
  }
end

Tool.find_or_create_by!(name: "write_step_note", kind: :internal) do |t|
  t.display_name = "Write Step Note"
  t.description = "Save a note for this step. Visible to agents in subsequent steps via workflow context."
  t.input_schema = {
    type: "object",
    properties: {
      note: { type: "string", description: "Note text to append" }
    },
    required: %w[note]
  }
end

Tool.find_or_create_by!(name: "code_climate", kind: :internal) do |t|
  t.display_name = "Code Climate Analysis"
  t.description = "Run Code Climate static analysis on a repository. Returns quality metrics, code smells, and maintainability scores."
  t.input_schema = {
    type: "object",
    properties: {
      repository_id: { type: "integer", description: "Repository ID to analyze" },
      engines: { type: "string", description: "Comma-separated engines (rubocop,eslint,duplication)" },
      format: { type: "string", description: "Output format: json or text", default: "json", enum: %w[json text] }
    },
    required: %w[repository_id]
  }
end

puts "  Internal tools created: #{Tool.internal_tools.count}"
```

### Current State in seeds.rb

There is already a `code_climate` internal tool seed at ~line 478. It needs to be consolidated with the 3 new workflow tool seeds into a single "Internal Tools" section.

### References

- [Source: db/seeds.rb] — existing seeds
- [Source: ai/epics/epic-18-internal-tools.md#Story 18.7]

## Dev Agent Record

### Agent Model Used
claude-4.6-opus-high

### Completion Notes List
- Consolidated 4 internal tool seeds into one section
- Updated code_climate description and default format to json
- Verified idempotency via rails runner

### File List
- db/seeds.rb (modified — internal tools section)
