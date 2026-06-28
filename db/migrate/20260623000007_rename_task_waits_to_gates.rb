# frozen_string_literal: true

# Rename the "wait" concept to "gate" everywhere: a CI wait is a gate on the
# column auto-trigger, not a trigger. Table task_waits → gates, column
# wait_type → gate_type. Also rename the internal tool record board_create_wait
# → board_create_gate (workflows reference tools by id, so the name change is
# safe; InternalTools::BoardCreateWait stays as a constant alias for any
# instruction text still using the old name).
class RenameTaskWaitsToGates < ActiveRecord::Migration[8.1]
  def up
    rename_table :task_waits, :gates
    rename_column :gates, :wait_type, :gate_type
    execute("UPDATE tools SET name = 'board_create_gate' WHERE name = 'board_create_wait'")
  end

  def down
    execute("UPDATE tools SET name = 'board_create_wait' WHERE name = 'board_create_gate'")
    rename_column :gates, :gate_type, :wait_type
    rename_table :gates, :task_waits
  end
end
