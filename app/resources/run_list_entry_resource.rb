# frozen_string_literal: true

# A workflow run as one row of the unified Sessions & Runs feed, carrying its
# step sessions as nested rows.
#
# The nested sessions are what makes the merge honest: a run's sessions are not
# peers of the run in the list, they are what the run is made of, so they expand
# under it instead of appearing seven rows away with no visible relationship.
class RunListEntryResource < ApplicationResource
  typelize_from WorkflowRun

  attributes :id, :mode, :started_at, :completed_at, :created_at

  # A run waiting for a session slot is itself `running`, so the row would claim
  # work is happening while nothing is. The step sessions are already loaded for
  # every other attribute here, so the honest answer costs no extra query.
  typelize :string
  attribute :state do |run|
    sessions = ordered_step_runs(run).filter_map { |sr| sr.terminal_session&.state }
    if sessions.include?("queued") && (sessions & %w[running ready finishing]).empty?
      "queued"
    else
      run.state
    end
  end

  typelize :string
  attribute :kind do |_run|
    "run"
  end

  typelize :string
  attribute :name do |run|
    run.workflow&.name.presence || "Workflow run"
  end

  typelize :string?
  attribute :user_name do |run|
    run.user&.name
  end

  # A run has no runtime of its own — it inherits the one its sessions used.
  # First step wins; a mixed-runtime run is rare and the row has no room to say
  # so, which is what the detail page is for.
  typelize :string?
  attribute :agent_type do |run|
    ordered_step_runs(run).filter_map { |sr| sr.terminal_session&.agent_type }.first
  end

  typelize :number
  attribute :total_tokens do |run|
    ordered_step_runs(run).sum { |sr| sr.terminal_session&.total_tokens.to_i }
  end

  typelize :number
  attribute :cost_cents do |run|
    ordered_step_runs(run).sum { |sr| sr.terminal_session&.cost_cents.to_i }
  end

  typelize :number
  attribute :steps_completed do |run|
    ordered_step_runs(run).count { |sr| sr.state.to_s == "completed" }
  end

  typelize :number
  attribute :steps_total do |run|
    run.step_runs_count
  end

  typelize "SessionListEntry[]"
  attribute :sessions do |run|
    ordered_step_runs(run).filter_map do |step_run|
      session = step_run.terminal_session
      next if session.nil?

      {
        "id" => session.id,
        "kind" => "session",
        "name" => "#{step_run.step&.name.presence || "Step #{step_run.step&.position}"} — session ##{session.id}",
        "state" => session.state,
        "sessionType" => session.session_type,
        "agentType" => session.agent_type,
        "mode" => session.mode,
        "totalTokens" => session.total_tokens,
        "costCents" => session.cost_cents,
        "startedAt" => session.started_at,
        "finishedAt" => session.finished_at,
        "createdAt" => session.created_at,
        "userName" => session.user&.name,
        "viewable" => true
      }
    end
  end

  # step_runs_count orders by nothing in particular; the list has to read in
  # execution order.
  def self.ordered_step_runs(run)
    run.step_runs.sort_by { |sr| [ sr.step&.position || 0, sr.created_at ] }
  end

  private

  # Every attribute above needs the same ordered list — memoized per resource
  # instance (one per run) so a single row doesn't re-sort it five times.
  def ordered_step_runs(run)
    @ordered_step_runs ||= self.class.ordered_step_runs(run)
  end
end
