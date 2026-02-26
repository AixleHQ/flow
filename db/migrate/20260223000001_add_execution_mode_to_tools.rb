# frozen_string_literal: true

class AddExecutionModeToTools < ActiveRecord::Migration[8.1]
  def change
    add_column :tools, :execution_mode, :string, null: false, default: "container"
  end
end
