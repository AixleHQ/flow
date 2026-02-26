# frozen_string_literal: true

class AddWorkflowOnlyToTools < ActiveRecord::Migration[8.0]
  def change
    add_column :tools, :workflow_only, :boolean, default: false, null: false
  end
end
