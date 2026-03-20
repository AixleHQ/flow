# frozen_string_literal: true

class CreateTaskWaits < ActiveRecord::Migration[7.2]
  def change
    create_table :task_waits do |t|
      t.references :board_task, null: false, foreign_key: { on_delete: :cascade }
      t.string :wait_type, null: false
      t.string :status, null: false, default: "pending"
      t.jsonb :metadata, null: false, default: {}
      t.jsonb :resolution_data, null: false, default: {}
      t.datetime :resolved_at

      t.timestamps
    end

    add_index :task_waits, :status
    add_index :task_waits, [ :wait_type, :status ]
  end
end
