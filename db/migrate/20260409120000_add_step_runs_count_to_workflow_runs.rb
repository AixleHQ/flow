# frozen_string_literal: true

class AddStepRunsCountToWorkflowRuns < ActiveRecord::Migration[8.1]
  def up
    add_column :workflow_runs, :step_runs_count, :integer, null: false, default: 0

    WorkflowRun.reset_column_information
    WorkflowRun.find_each { |run| WorkflowRun.reset_counters(run.id, :step_runs) }
  end

  def down
    remove_column :workflow_runs, :step_runs_count
  end
end
