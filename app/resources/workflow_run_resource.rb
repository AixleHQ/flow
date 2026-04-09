# frozen_string_literal: true

class WorkflowRunResource < ApplicationResource
  attributes :id, :workflow_id, :project_id, :user_id,
             :state, :started_at, :completed_at,
             :created_at, :updated_at

  attribute :mode do |run|
    run.mode.to_s
  end

  attribute :workflow_name do |run|
    run.workflow&.name
  end

  attribute :steps_completed do |run|
    if run.association(:step_runs).loaded?
      run.step_runs.to_a.count { |sr| sr.state.to_s == "completed" }
    else
      run.step_runs.where(state: :completed).count
    end
  end

  attribute :steps_total do |run|
    run.step_runs_count
  end

  attribute :user_name do |run|
    run.user&.name
  end

  attribute :agent_type do |run|
    run.step_runs.first&.terminal_session&.agent_type
  end

  attribute :cost_cents do |run|
    run.step_runs.sum { |sr| sr.terminal_session&.cost_cents.to_i }
  end

  attribute :step_runs do |run|
    step_name_map = run.workflow.steps.each_with_object({}) { |s, h| h[s.id] = s.name }
    traefik = { ws_base: Settings.traefik.ws_base, http_base: Settings.traefik.http_base }

    run.step_runs.sort_by(&:created_at).map do |sr|
      StepRunResource.new(sr, params: { step_name_map: step_name_map, traefik: traefik }).to_h
    end
  end
end
