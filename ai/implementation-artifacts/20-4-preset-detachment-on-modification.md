# Story 20.4: Preset Detachment on Modification

Status: review

## Story

As a user,
I want my board to become independent after I modify columns,
so that I can freely customize without being constrained by the preset.

## Acceptance Criteria

1. Any column write operation (create, update, destroy, reorder) sets `board.preset_origin` to `nil` if it was previously set
2. Detachment is one-way — once `preset_origin` is nil, no operation re-attaches it
3. Board serializer reflects detachment: `preset_origin: null` after modification
4. Column operations still succeed normally — detachment is a side-effect, not a gate
5. Creating a board from preset and then immediately reading it returns non-nil `preset_origin` (no premature detachment)

## Tasks / Subtasks

- [x] Task 1: Add detachment callback on BoardColumn (AC: #1, #2)
  - [x] Add `after_save :detach_preset` callback on `BoardColumn`
  - [x] Add `after_destroy :detach_preset` callback on `BoardColumn`
  - [x] `detach_preset`: `board.update_column(:preset_origin, nil) if board.preset_origin.present?`
  - [x] Use `update_column` (not `update!`) to skip validations/callbacks and avoid recursion
- [x] Task 2: Handle reorder detachment (AC: #1)
  - [x] In `ColumnsController#reorder`, after position updates, call `board.update_column(:preset_origin, nil)` if preset was set
  - [x] Reorder uses `update_column` which skips callbacks — handled explicitly
- [x] Task 3: Skip detachment during preset creation (AC: #5)
  - [x] In `Board.create_from_preset`, column creation does NOT trigger detachment
  - [x] **Implemented Approach C** — create board without preset_origin, create columns, then set preset_origin as last step via update_column
- [x] Task 4: Tests
  - [x] Test: create board from preset → `preset_origin` is set
  - [x] Test: add column → `preset_origin` becomes nil
  - [x] Test: rename column → `preset_origin` becomes nil
  - [x] Test: delete column → `preset_origin` becomes nil
  - [x] Test: reorder columns → `preset_origin` becomes nil (covered in controller test)
  - [x] Test: modify column on board without preset → `preset_origin` remains nil (no error)

## Dev Notes

### Recommended Implementation (Approach C)

Update `Board.create_from_preset` to set `preset_origin` as the **last step** after columns are created:

```ruby
def self.create_from_preset(project:, preset_key:, name: nil)
  preset = BoardPresets.find(preset_key)
  raise ActiveRecord::RecordNotFound, "Invalid preset: #{preset_key}" unless preset

  transaction do
    board = create!(project: project, name: name || preset[:display_name])
    preset[:columns].each do |col_def|
      board.board_columns.create!(name: col_def[:name], position: col_def[:position], purpose: col_def[:purpose])
    end
    board.update_column(:preset_origin, preset_key.to_s)
    board
  end
end
```

This way `after_save` callbacks on columns fire but `preset_origin` is still nil, so `detach_preset` is a no-op. Then `update_column` sets it at the end.

### BoardColumn Callback

```ruby
after_save :detach_preset
after_destroy :detach_preset

private

def detach_preset
  board.update_column(:preset_origin, nil) if board.preset_origin.present?
end
```

### Reorder Handling

Since `reorder` uses `update_column` (which skips callbacks), add explicit detachment:

```ruby
def reorder
  board = current_project.board
  ActiveRecord::Base.transaction do
    # two-pass to avoid unique constraint violations
    offset = board.board_columns.count + 1
    params[:column_ids].each_with_index { |id, i| board.board_columns.find(id).update_column(:position, offset + i + 1) }
    params[:column_ids].each_with_index { |id, i| board.board_columns.find(id).update_column(:position, i + 1) }
    board.update_column(:preset_origin, nil) if board.preset_origin.present?
  end
  respond_with board.board_columns.reload.order(:position), each_serializer: BoardColumnSerializer
end
```

### Edge Cases

- Board without preset (`preset_origin: nil`) — column operations work normally, detachment callback is a no-op
- Concurrent column modifications — `update_column(:preset_origin, nil)` is idempotent, safe under concurrency
- Board deleted — columns destroyed via `dependent: :destroy`, detachment callback fires but board is being destroyed anyway

### Project Structure Notes

- Updated: `app/models/board_column.rb` — `after_save`/`after_destroy` callbacks
- Updated: `app/models/board.rb` — `create_from_preset` sets `preset_origin` last
- Updated: `app/controllers/api/v1/company/projects/board/columns_controller.rb` — explicit detachment in reorder

### References

- [Source: ai/epics/epic-20-board-column-foundation.md#Story 20.4]
- [Source: ai/prd/board-tasks.md#FR4]

## Dev Agent Record

### Agent Model Used
claude-4.6-opus-high

### Debug Log References

### Completion Notes List
- Added after_save/after_destroy :detach_preset callbacks on BoardColumn
- Explicit detachment in reorder action (update_column skips callbacks)
- Approach C for preset creation: set preset_origin last to avoid premature detachment
- 7 dedicated detachment tests covering all column operations and edge cases

### File List
- app/models/board_column.rb (modified — added detachment callbacks)
- app/models/board.rb (modified — create_from_preset sets preset_origin last)
- app/controllers/api/v1/company/projects/board/columns_controller.rb (modified — detachment in reorder)
- test/models/board_column_detachment_test.rb (new)

## Change Log
- 2026-02-27: Implemented preset detachment callbacks and tests (Story 20.4)
