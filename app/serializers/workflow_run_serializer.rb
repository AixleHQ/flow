# frozen_string_literal: true

class WorkflowRunSerializer < ApplicationSerializer
  attributes :id, :workflow_id, :project_id, :user_id,
             :state, :mode,
             :input_asset_ids, :shared_context,
             :repository_ids, :agent_runtime,
             :step_overrides,
             :started_at, :completed_at,
             :created_at, :updated_at

  attribute :workflow_name
  attribute :current_step_info

  has_many :step_runs, serializer: StepRunSerializer, if: :include_associations

  def mode
    object.mode.to_s
  end

  def workflow_name
    object.workflow.name
  end

  def current_step_info
    current = object.step_runs
      .select { |sr| %w[pending running waiting_input].include?(sr.state) }
      .min_by(&:created_at)
    return nil unless current

    {
      id: current.id,
      step_id: current.step_id,
      step_name: current.step.name,
      step_position: current.step.position,
      state: current.state,
      terminal_session_id: current.terminal_session_id
    }
  end
end
