# frozen_string_literal: true

# Lean serialization for the project workflow runs list (no step_runs payload, agent_type, or cost).
class WorkflowRunIndexResource < ApplicationResource
  typelize_from WorkflowRun

  attributes :id, :workflow_id, :project_id, :user_id,
             :state, :started_at, :completed_at, :created_at, :updated_at

  typelize :string
  attribute :mode do |run|
    run.mode.to_s
  end

  typelize :string?
  attribute :workflow_name do |run|
    run.workflow&.name
  end

  typelize :number
  attribute :steps_completed do |run|
    if run.association(:step_runs).loaded?
      run.step_runs.to_a.count { |sr| sr.state.to_s == "completed" }
    else
      run.step_runs.where(state: :completed).count
    end
  end

  typelize :number
  attribute :steps_total do |run|
    run.step_runs_count
  end
end
