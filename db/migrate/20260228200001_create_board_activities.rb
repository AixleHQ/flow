# frozen_string_literal: true

class CreateBoardActivities < ActiveRecord::Migration[8.0]
  def change
    create_table :board_activities do |t|
      t.references :board, null: false, foreign_key: true
      t.references :board_task, foreign_key: true, null: true
      t.string :event_type, null: false
      t.references :actor, foreign_key: { to_table: :users }, null: false
      t.string :actor_type, null: false
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false
    end

    add_index :board_activities, [ :board_id, :created_at ]
    add_index :board_activities, [ :board_task_id, :created_at ]
    add_index :board_activities, :event_type
  end
end
