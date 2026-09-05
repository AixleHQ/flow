# frozen_string_literal: true

class WorkflowRunResource < ApplicationResource
  attributes :id, :workflow_id, :project_id, :user_id,
             :state, :started_at, :completed_at,
             :created_at, :updated_at,
             :failure_reason, :failed_agent_credential_id

  attribute :mode do |run|
    run.mode.to_s
  end

  typelize :string?
  attribute :failed_account_name do |run|
    run.failed_agent_credential&.agent_type
  end

  typelize :string?
  attribute :workflow_name do |run|
    run.workflow&.name
  end

  # The run header's description line — what this workflow does, which is a
  # property of the workflow, not of this particular execution.
  typelize :string?
  attribute :workflow_description do |run|
    run.workflow&.description
  end

  typelize :number
  attribute :total_tokens do |run|
    run.step_runs.sum { |sr| sr.terminal_session&.total_tokens.to_i }
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

  typelize :string?
  attribute :user_name do |run|
    run.user&.name
  end

  # May the viewer steer this run (cancel / approve / retry / skip)? Mirrors
  # WorkflowRunsPolicy so the buttons match what the POST would actually do;
  # the policy is the enforcement, this is only what the page renders. Pass
  # `params: { viewer: current_user }` — without the param it stays true, for
  # the broadcast payloads that have no single viewer.
  typelize :boolean
  attribute :controllable_by_viewer do |run|
    params.key?(:viewer) ? run.controllable_by?(params[:viewer]) : true
  end

  typelize :string?
  attribute :agent_type do |run|
    run.step_runs.first&.terminal_session&.agent_type
  end

  typelize :number
  attribute :cost_cents do |run|
    run.step_runs.sum { |sr| sr.terminal_session&.cost_cents.to_i }
  end

  typelize "StepRun[]"
  attribute :step_runs do |run|
    step_name_map = run.workflow.steps.each_with_object({}) { |s, h| h[s.id] = s.name }
    traefik = { ws_base: Settings.traefik.ws_base, http_base: Settings.traefik.http_base }

    run.step_runs.sort_by(&:created_at).map do |sr|
      StepRunResource.new(sr, params: { step_name_map: step_name_map, traefik: traefik }).to_h
    end
  end
end
