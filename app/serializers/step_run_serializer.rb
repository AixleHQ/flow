# frozen_string_literal: true

class StepRunSerializer < ApplicationSerializer
  attributes :id, :workflow_run_id, :step_id, :terminal_session_id,
             :state, :step_note, :skip_reason, :error_message,
             :started_at, :completed_at, :created_at

  attribute :step_name
  attribute :step_position
  attribute :sub_step_runs
  attribute :past_failures

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

  def past_failures
    return [] unless include_associations

    object.workflow_run.step_runs
      .where(step_id: object.step_id, state: :failed)
      .where.not(id: object.id)
      .order(created_at: :asc)
      .map { |sr| { error_message: sr.error_message, failed_at: sr.completed_at&.iso8601 } }
  end
end
