# frozen_string_literal: true

class StepRunSerializer < ApplicationSerializer
  attributes :id, :workflow_run_id, :step_id, :terminal_session_id,
             :state, :step_note, :skip_reason, :error_message,
             :started_at, :completed_at

  attribute :step_name
  attribute :step_position

  has_many :sub_step_runs, serializer: SubStepRunSerializer, if: :include_associations

  def step_name
    object.step.name
  end

  def step_position
    object.step.position
  end
end
