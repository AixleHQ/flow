# frozen_string_literal: true

# Board load optimization: archiving lets finished tasks (typically the Done
# column) drop out of the default board load. `archived_at` is nil for active
# tasks; the board page and API only load active tasks unless archived are
# explicitly requested. The index keeps the "active tasks for a board" query
# (board_id + archived_at IS NULL) fast on heavy boards.
class AddArchivedAtToBoardTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :board_tasks, :archived_at, :datetime
    add_index :board_tasks, %i[board_id archived_at]
  end
end
