# Story 20.3: Board Presets

Status: review

## Story

As a user,
I want to create a board from a preset template,
so that I get a sensible starting point without configuring everything from scratch.

## Acceptance Criteria

1. Three built-in presets defined in `BoardPresets` module:
   - **simple_kanban:** Backlog, In Progress, Done
   - **dev_team:** Backlog, Tech Design, Implementation, Code Review, Done
   - **full_sdlc:** Backlog, Estimation, Tech Design, Implementation, Code Review, QA, Done
2. Each preset defines column names, positions (1-based), and default `purpose` texts
3. Board creation with `preset` parameter creates board + all preset columns in single transaction
4. `preset_origin` field records which preset key was used (e.g. `"dev_team"`)
5. Board creation without `preset` creates empty board (no columns)
6. API endpoint `GET /board/presets` returns available preset definitions
7. Preset validation: invalid preset key returns 422 error

## Tasks / Subtasks

- [x] Task 1: Create BoardPresets module (AC: #1, #2)
  - [x] `app/services/board_presets.rb`
  - [x] Define `PRESETS` as frozen hash with 3 presets
  - [x] Each preset: `{ name: "...", columns: [{ name:, position:, purpose: }] }`
  - [x] Class methods: `.all` (returns all presets), `.find(key)` (returns one or nil), `.valid?(key)`
- [x] Task 2: Purpose texts for each preset column (AC: #2)
  - [x] Simple Kanban: generic stage descriptions
  - [x] Dev Team: agent-oriented purpose texts (Tech Design: "Agent analyzes requirements and produces tech design document as comment with tag 'tech_design'")
  - [x] Full SDLC: detailed purpose texts for each stage
- [x] Task 3: Update Board model for preset creation (AC: #3, #4, #5)
  - [x] Add `create_from_preset(project:, preset_key:, name:)` class method on Board
  - [x] Wraps in `ActiveRecord::Base.transaction`
  - [x] Creates Board with `preset_origin: preset_key` (set last to avoid premature detachment)
  - [x] Creates all columns from preset definition
  - [x] If no preset, just creates board with given name and no columns
- [x] Task 4: Update BoardsController create action (AC: #3, #5, #7)
  - [x] If `params[:board][:preset]` present → validate and create from preset
  - [x] If no preset → create empty board
  - [x] Invalid preset → 422 with error message
  - [x] Board name: from params, or default from preset (e.g., "Dev Team Board")
- [x] Task 5: Add presets endpoint (AC: #6)
  - [x] Add `collection { get :presets }` to board routes
  - [x] `BoardsController#presets` action returns preset definitions as JSON
- [x] Task 6: Tests
  - [x] Unit test for `BoardPresets` module (10 tests)
  - [x] Model test: `Board.create_from_preset` creates correct columns (4 tests)
  - [x] Controller test: create with preset, create without preset, invalid preset, presets endpoint (6 tests)

## Dev Notes

### BoardPresets Module

```ruby
class BoardPresets
  PRESETS = {
    simple_kanban: { display_name: "Simple Kanban", columns: [...] },
    dev_team: { display_name: "Dev Team", columns: [...] },
    full_sdlc: { display_name: "Full SDLC", columns: [...] }
  }.freeze

  def self.all = PRESETS.map { |key, data| { key:, display_name:, columns: names } }
  def self.find(key) = PRESETS[key.to_sym]
  def self.valid?(key) = PRESETS.key?(key.to_sym)
end
```

### Board.create_from_preset

Uses Approach C from Story 20.4: creates board without preset_origin, creates columns, then sets preset_origin last via `update_column` to avoid premature detachment from callbacks.

### Presets API Response

```
GET /api/v1/company/projects/:project_id/board/presets
```

```json
[
  { "key": "simple_kanban", "display_name": "Simple Kanban", "columns": ["Backlog", "In Progress", "Done"] },
  { "key": "dev_team", "display_name": "Dev Team", "columns": ["Backlog", "Tech Design", "Implementation", "Code Review", "Done"] },
  { "key": "full_sdlc", "display_name": "Full SDLC", "columns": ["Backlog", "Estimation", "Tech Design", "Implementation", "Code Review", "QA", "Done"] }
]
```

### Project Structure Notes

- `app/services/board_presets.rb` — preset definitions (frozen constants, NOT DB records)
- Updated: `app/models/board.rb` — `create_from_preset` class method
- Updated: `app/controllers/api/v1/company/projects/boards_controller.rb` — preset handling in create, `presets` action

### References

- [Source: ai/epics/epic-20-board-column-foundation.md#Story 20.3]
- [Source: ai/prd/board-tasks.md#FR1]
- [Source: ai/prd/board-tasks.md#Board Management]

## Dev Agent Record

### Agent Model Used
claude-4.6-opus-high

### Debug Log References

### Completion Notes List
- BoardPresets service with 3 frozen preset definitions (simple_kanban, dev_team, full_sdlc)
- Each preset has agent-oriented purpose texts for columns
- Board.create_from_preset class method with transaction, sets preset_origin last (Approach C)
- BoardsController updated: preset param handling, validation, presets endpoint
- 20 tests for BoardPresets module + model + controller preset operations

### File List
- app/services/board_presets.rb (new)
- app/models/board.rb (modified — added create_from_preset)
- app/controllers/api/v1/company/projects/boards_controller.rb (modified — preset handling + presets action)
- config/routes.rb (modified — added presets collection route)
- test/services/board_presets_test.rb (new)
- test/models/board_test.rb (modified — added create_from_preset tests)
- test/controllers/api/v1/company/projects/boards_controller_test.rb (modified — added preset tests)

## Change Log
- 2026-02-27: Implemented BoardPresets service, create_from_preset, presets endpoint, and tests (Story 20.3)
