# frozen_string_literal: true

class CreateColumnTransitions < ActiveRecord::Migration[8.0]
  def change
    create_table :column_transitions do |t|
      t.references :board_task, null: false, foreign_key: true
      t.references :from_column, foreign_key: { to_table: :board_columns }, null: true
      t.references :to_column, foreign_key: { to_table: :board_columns }, null: false
      t.references :actor, foreign_key: { to_table: :users }, null: false
      t.string :actor_type, null: false
      t.references :workflow_run, foreign_key: true, null: true
      t.datetime :created_at, null: false
    end
  end
end
