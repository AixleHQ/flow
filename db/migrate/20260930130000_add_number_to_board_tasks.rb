# frozen_string_literal: true

# Task numbers shown on the board (#1, #2, …) restart on every board instead of
# being the global board_tasks.id. `boards.last_task_number` is the counter new
# tasks draw from; it only ever grows, so a deleted task's number is never
# handed to another task and old links to `?n=N` cannot start pointing
# elsewhere.
class AddNumberToBoardTasks < ActiveRecord::Migration[8.1]
  def up
    add_column :boards, :last_task_number, :integer, null: false, default: 0
    add_column :board_tasks, :number, :integer

    backfill

    change_column_null :board_tasks, :number, false
    add_index :board_tasks, %i[board_id number], unique: true
    add_check_constraint :board_tasks, "number > 0", name: "board_tasks_number_positive"
  end

  def down
    remove_check_constraint :board_tasks, name: "board_tasks_number_positive"
    remove_index :board_tasks, %i[board_id number]
    remove_column :board_tasks, :number
    remove_column :boards, :last_task_number
  end

  def backfill
    execute(<<~SQL.squish)
      UPDATE board_tasks SET number = ranked.rn
      FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY board_id ORDER BY created_at, id) AS rn
        FROM board_tasks
      ) ranked
      WHERE board_tasks.id = ranked.id
    SQL

    execute(<<~SQL.squish)
      UPDATE boards
      SET last_task_number = COALESCE((SELECT MAX(number) FROM board_tasks WHERE board_tasks.board_id = boards.id), 0)
    SQL
  end
end
