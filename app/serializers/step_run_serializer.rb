# frozen_string_literal: true

class StepRunSerializer < ApplicationSerializer
  attributes :id, :workflow_run_id, :step_id, :terminal_session_id,
             :state, :step_note, :skip_reason, :error_message,
             :started_at, :completed_at

  attribute :step_name
  attribute :step_position
  attribute :sub_step_runs

  def step_name
    object.step.name
  end

  def step_position
    object.step.position
  end

  def sub_step_runs
    return [] unless include_associations

    object.sub_step_runs.includes(:sub_step).sort_by { |ssr| ssr.sub_step&.position || 0 }.map do |ssr|
      SubStepRunSerializer.new(ssr).serializable_hash
    end
  end
end
