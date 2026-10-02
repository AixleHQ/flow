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
    create_number_trigger

    change_column_null :board_tasks, :number, false
    add_index :board_tasks, %i[board_id number], unique: true
    add_check_constraint :board_tasks, "number > 0", name: "board_tasks_number_positive"
  end

  def down
    drop_number_trigger
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

  # Pods still on the previous release keep inserting tasks without a number
  # until the rolling deploy replaces them; this fills it from the same counter
  # Board#next_task_number! uses. schema.rb cannot carry triggers, so the test
  # database never has it — a follow-up migration drops it once no old pod is left.
  def create_number_trigger
    execute(<<~SQL)
      CREATE FUNCTION board_tasks_assign_number() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF NEW.number IS NULL THEN
          UPDATE boards SET last_task_number = last_task_number + 1
          WHERE id = NEW.board_id
          RETURNING last_task_number INTO NEW.number;
        END IF;
        RETURN NEW;
      END
      $$;

      CREATE TRIGGER board_tasks_assign_number BEFORE INSERT ON board_tasks
        FOR EACH ROW EXECUTE FUNCTION board_tasks_assign_number();
    SQL
  end

  def drop_number_trigger
    execute(<<~SQL)
      DROP TRIGGER IF EXISTS board_tasks_assign_number ON board_tasks;
      DROP FUNCTION IF EXISTS board_tasks_assign_number();
    SQL
  end
end
