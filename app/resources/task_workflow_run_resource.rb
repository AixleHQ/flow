# frozen_string_literal: true

class TaskWorkflowRunResource < ApplicationResource
  typelize_from WorkflowRun

  attributes :id, :state, :mode, :started_at, :completed_at, :created_at

  typelize :string?
  attribute :workflow_name do |run|
    run.workflow&.name
  end

  typelize :number?
  attribute :total_cost_cents do |run|
    run.respond_to?(:total_cost_cents) ? run.total_cost_cents : nil
  end

  typelize :number?
  attribute :duration_seconds do |run|
    next nil unless run.started_at && run.completed_at
    duration = (run.completed_at - run.started_at).round
    duration >= 0 ? duration : nil
  end

  typelize "{ name: string; state: string; startedAt: string | null; finishedAt: string | null; " \
           "durationSeconds: number | null; terminalSessionId: number | null }[]"
  attribute :steps do |run|
    (run.step_runs || []).includes(:step).order(:created_at).map do |sr|
      dur = sr.started_at && sr.completed_at ? (sr.completed_at - sr.started_at).round : nil
      {
        name: sr.step&.name || "Step",
        state: sr.state.to_s,
        startedAt: sr.started_at&.iso8601,
        finishedAt: sr.completed_at&.iso8601,
        durationSeconds: dur && dur >= 0 ? dur : nil,
        # Lets the board task drawer link straight into the step's terminal session
        # instead of routing the user through the workflow run page.
        terminalSessionId: sr.terminal_session_id
      }
    end
  end
end
