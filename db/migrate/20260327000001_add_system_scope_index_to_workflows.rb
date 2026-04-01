# frozen_string_literal: true

class AddSystemScopeIndexToWorkflows < ActiveRecord::Migration[7.2]
  def change
    add_index :workflows, :scope_type,
              name: "index_workflows_on_system_scope",
              where: "scope_type = 'System'"
  end
end
