# frozen_string_literal: true

# Step-level config item attachments, matching the jsonb id lists the step
# already carries for tools, skills, MCP servers, assets and repositories.
class AddConfigItemIdsToSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :steps, :config_item_ids, :jsonb, default: [], null: false
  end
end
