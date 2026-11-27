# frozen_string_literal: true

# Integrations chosen per session (docs/design/session-integrations.md §4): an integration as one
# more kind of entry in a step's or a workflow's resource list, and the set a session was
# built with. Nothing reads either yet, so behaviour does not change.
class AddSessionIntegrations < ActiveRecord::Migration[8.1]
  LINK_KINDS = %w[tool_id skill_id mcp_server_id asset_id repository_id config_item_id aws_oidc_role_id].freeze

  def up
    %i[step_resource_links workflow_resource_links].each do |table|
      add_reference table, :integration, foreign_key: { on_delete: :cascade }, index: false
      owner = table == :step_resource_links ? :step_id : :workflow_id
      add_index table, [ owner, :integration_id ], unique: true, where: "integration_id IS NOT NULL"
      add_index table, :integration_id, where: "integration_id IS NOT NULL"
      replace_one_resource_check(table, LINK_KINDS + %w[integration_id])
    end

    create_table :session_integrations, id: false do |t|
      t.references :terminal_session, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :integration, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.index %i[terminal_session_id integration_id], unique: true, name: "index_session_integrations_on_pair"
    end
  end

  def down
    drop_table :session_integrations
    %i[step_resource_links workflow_resource_links].each do |table|
      execute "DELETE FROM #{table} WHERE integration_id IS NOT NULL"
      replace_one_resource_check(table, LINK_KINDS)
      remove_reference table, :integration, foreign_key: true, index: false
    end
  end

  private

  def replace_one_resource_check(table, columns)
    remove_check_constraint table, name: "#{table}_one_resource"
    add_check_constraint table, "num_nonnulls(#{columns.join(', ')}) = 1", name: "#{table}_one_resource"
  end
end
