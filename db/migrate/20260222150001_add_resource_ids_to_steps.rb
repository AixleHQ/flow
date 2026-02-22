# frozen_string_literal: true

class AddResourceIdsToSteps < ActiveRecord::Migration[8.0]
  def change
    add_column :steps, :mcp_server_ids, :jsonb, default: [], null: false
    add_column :steps, :skill_ids, :jsonb, default: [], null: false
    add_column :steps, :repository_ids, :jsonb, default: [], null: false
  end
end
