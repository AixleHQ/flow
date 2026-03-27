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

    object.sub_step_runs.sort_by { |ssr| ssr.sub_step&.position || 0 }.map do |ssr|
      SubStepRunSerializer.new(ssr).serializable_hash
    end
  end

  def past_failures
    return [] unless include_associations

    object.workflow_run.step_runs
      .select { |sr| sr.step_id == object.step_id && sr.state == "failed" && sr.id != object.id }
      .sort_by(&:created_at)
      .map { |sr| { error_message: sr.error_message, failed_at: sr.completed_at&.iso8601 } }
  end
end
