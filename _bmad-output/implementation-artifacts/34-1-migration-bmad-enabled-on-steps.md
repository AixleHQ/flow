# Story 34.1: Migration — bmad_enabled on Steps

Status: ready-for-dev

## Story

As a **workflow builder admin**,
I want a `bmad_enabled` boolean field on the `steps` table,
so that BMAD can be configured per-step independently of the session-level setting.

## Acceptance Criteria

1. **Given** the migration is applied
   **When** the `steps` table schema is inspected
   **Then** a `bmad_enabled` column exists with type `boolean`, default `false`, not null

2. **Given** an existing step without BMAD configuration
   **When** the migration runs
   **Then** all existing steps have `bmad_enabled = false`

3. **Given** a new step is created with `bmad_enabled: true`
   **When** the step record is persisted
   **Then** `step.bmad_enabled` returns `true`

4. **Given** the API receives `bmad_enabled: true` in step params
   **When** the step is created or updated
   **Then** the field is persisted correctly

5. **Given** the API serializes a step
   **When** the response is returned
   **Then** `bmad_enabled` is included in the JSON payload

## Tasks / Subtasks

- [ ] Task 1: Create migration (AC: #1, #2)
  - [ ] `rails generate migration AddBmadEnabledToSteps bmad_enabled:boolean`
  - [ ] Set `default: false, null: false`
  - [ ] Run migration, verify schema.rb updated
- [ ] Task 2: Update Step model (AC: #3)
  - [ ] No model changes needed — boolean column just works with ActiveRecord
  - [ ] Optionally add a comment noting the BMAD integration purpose
- [ ] Task 3: Update StepsActions strong params (AC: #4)
  - [ ] Add `:bmad_enabled` to `step_params` permit list in `app/controllers/concerns/steps_actions.rb`
- [ ] Task 4: Update Step serializer (AC: #5)
  - [ ] Add `bmad_enabled` to the Step serializer attributes
- [ ] Task 5: Write tests (AC: #1–#5)
  - [ ] Test step creation with bmad_enabled: true
  - [ ] Test default value is false
  - [ ] Test API permits and returns bmad_enabled

## Dev Notes

- **Migration pattern:** Follows existing boolean columns on steps: `allow_non_interactive` (default: false, null: false) and `mount_repositories` (default: true, null: false) — see schema.rb lines 481–505
- **Strong params file:** `app/controllers/concerns/steps_actions.rb` lines 49–61
  ```ruby
  def step_params
    params.require(:step).permit(
      :name, :description, :instructions, :position, :agent_id,
      :allow_non_interactive, :skip_policy, :on_failure, :max_retries,
      :mount_repositories, :required_agent_runtime,
      # ... add :bmad_enabled here
    )
  end
  ```
- **Model file:** `app/models/step.rb` — no changes needed beyond the migration
- **Serializer:** Find the Step serializer (likely `app/serializers/step_serializer.rb`) and add `bmad_enabled`
- **Factory:** Update `test/factories/steps.rb` to include `bmad_enabled` trait if needed

### Project Structure Notes

- Consistent with existing boolean patterns on steps table
- Migration is reversible by default (`remove_column :steps, :bmad_enabled`)

### References

- [Source: db/schema.rb#L481-505] — steps table schema
- [Source: app/controllers/concerns/steps_actions.rb#L49-61] — step_params
- [Source: app/models/step.rb] — Step model
- [Source: ai/epics/epic-34-bmad-workflow-step.md#Story-34.1] — story spec

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
