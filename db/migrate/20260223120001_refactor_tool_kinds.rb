# frozen_string_literal: true

class RefactorToolKinds < ActiveRecord::Migration[8.1]
  def up
    # Migrate existing workflow_only internal tools → kind: "workflow"
    execute <<~SQL
      UPDATE tools SET kind = 'workflow'
      WHERE kind = 'internal' AND workflow_only = true
    SQL

    # Migrate container-mode internal tools → kind: "system"
    execute <<~SQL
      UPDATE tools SET kind = 'system'
      WHERE kind = 'internal' AND execution_mode = 'container'
    SQL

    # Remaining internal tools (app mode, non-workflow) stay as "internal"

    remove_column :tools, :workflow_only
  end

  def down
    add_column :tools, :workflow_only, :boolean, default: false, null: false

    execute <<~SQL
      UPDATE tools SET kind = 'internal', workflow_only = true
      WHERE kind = 'workflow'
    SQL

    execute <<~SQL
      UPDATE tools SET kind = 'internal'
      WHERE kind = 'system'
    SQL
  end
end
