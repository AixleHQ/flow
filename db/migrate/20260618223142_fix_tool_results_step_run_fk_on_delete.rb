# frozen_string_literal: true

# Deleting a Workflow purges step_runs (delete_all), but tool_results.step_run_id
# -> step_runs was RESTRICT, raising ActiveRecord::InvalidForeignKey
# (Sentry PALAD-AI-RAILS-1K). Nullify to keep tool-result audit rows (TTL-pruned
# by ToolResultCleanupJob), mirroring the workflow_run_assets fix (20260601053713).
class FixToolResultsStepRunFkOnDelete < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :tool_results, :step_runs
    add_foreign_key :tool_results, :step_runs, on_delete: :nullify
  end

  def down
    remove_foreign_key :tool_results, :step_runs
    add_foreign_key :tool_results, :step_runs
  end
end
