# frozen_string_literal: true

class TaskWorkflowRunResource < ApplicationResource
  typelize_from WorkflowRun

  attributes :id, :state, :mode, :started_at, :completed_at, :created_at

  typelize "string | null"
  attribute :workflow_name do |run|
    run.workflow&.name
  end

  typelize "number | null"
  attribute :total_cost_cents do |run|
    run.respond_to?(:total_cost_cents) ? run.total_cost_cents : nil
  end

  typelize "number | null"
  attribute :duration_seconds, &:execution_seconds

  typelize "{ name: string; state: string; startedAt: string | null; finishedAt: string | null; " \
           "durationSeconds: number | null; terminalSessionId: number | null }[]"
  attribute :steps do |run|
    # A caller that preloaded `step_runs: [:step, :terminal_session]` gets no further queries; `.includes`
    # here would discard that preload and re-query per run (an N+1 on the board, which
    # renders this for every run of the selected task).
    ordered = if run.association(:step_runs).loaded?
      run.step_runs.sort_by(&:created_at)
    else
      run.step_runs.includes(:step, :terminal_session).order(:created_at).to_a
    end

    ordered.map do |sr|
      {
        name: sr.step&.name || "Step",
        state: sr.state.to_s,
        startedAt: sr.started_at&.iso8601,
        finishedAt: sr.completed_at&.iso8601,
        durationSeconds: sr.execution_seconds,
        # Lets the board task drawer link straight into the step's terminal session
        # instead of routing the user through the workflow run page.
        terminalSessionId: sr.terminal_session_id
      }
    end
  end
end
