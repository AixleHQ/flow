# frozen_string_literal: true

class MoveRuntimeConfigToWorkflowRuns < ActiveRecord::Migration[8.0]
  def change
    # Repositories and runtime are run-level concerns, not step-level
    add_column :workflow_runs, :repository_ids, :jsonb, default: [], null: false
    add_column :workflow_runs, :agent_runtime, :string

    # Steps only need a flag: should repos be mounted for this step?
    add_column :steps, :mount_repositories, :boolean, default: true, null: false

    remove_column :steps, :repository_ids, :jsonb, default: [], null: false
    remove_column :steps, :agent_runtime, :string
  end
end
