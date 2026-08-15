# frozen_string_literal: true

class BoardTaskResource < ApplicationResource
  # Gates shown per task in `ci_gates`. A task normally has one or two; the cap is
  # only there so a card that was re-run all day cannot bloat the board payload.
  CI_GATE_LIMIT = 5

  # Shared shape of both gate collections below. Nested keys are serialized as
  # written here (only top-level attribute names are camelized by Alba); the
  # Inertia prop transformer camelizes the whole tree for the web client.
  GATE_TYPE = "Array<{ id: number; gate_type: string; status: string; ci_status: string; " \
              "conclusion: string | null; metadata: Record<string, unknown>; " \
              "source: Record<string, unknown>; age_seconds: number; expires_at: string; " \
              "expired: boolean; diagnostic_reason: string | null; created_at: string; " \
              "resolved_at: string | null }>"

  # One gate as the board and the agent tools see it. `age_seconds`/`expires_at`
  # make a wait legible (how long, and how much longer), `source` names the
  # repository and run/check the gate is bound to, and `diagnostic_reason` says why
  # a stale gate gave up.
  def self.gate_payload(gate, now: Time.current)
    {
      id: gate.id,
      gate_type: gate.gate_type.to_s,
      status: gate.status.to_s,
      ci_status: gate.ci_status,
      conclusion: gate.conclusion,
      metadata: gate.metadata,
      source: gate.source,
      age_seconds: gate.age_seconds(now),
      expires_at: gate.expires_at&.iso8601,
      expired: gate.expired?(now),
      diagnostic_reason: gate.diagnostic_reason,
      created_at: gate.created_at.iso8601,
      resolved_at: gate.resolved_at&.iso8601
    }
  end

  attributes :id, :title, :description, :task_type, :priority,
             :assignee_id, :board_column_id, :position,
             :parent_task_id, :tags, :created_at, :updated_at

  typelize :string?
  attribute :assignee_name do |task|
    task.assignee&.name
  end

  typelize :boolean
  attribute :archived do |task|
    task.archived?
  end

  typelize :number
  attribute :comments_count do |task|
    task.has_attribute?(:comments_count) ? task[:comments_count].to_i : task.task_comments.size
  end

  typelize :number
  attribute :children_count do |task|
    task.has_attribute?(:children_count) ? task[:children_count].to_i : task.child_tasks.size
  end

  typelize :number
  attribute :assets_count do |task|
    task.has_attribute?(:assets_count) ? task[:assets_count].to_i : task.task_assets.size
  end

  typelize "Array<{ id: number; state: string; created_at: string }>"
  attribute :recent_workflow_runs do |task|
    task.workflow_runs.sort_by(&:created_at).last(5).reverse.map do |run|
      { id: run.id, state: run.state, created_at: run.created_at.iso8601 }
    end
  end

  typelize GATE_TYPE
  attribute :pending_gates do |task|
    gates = if task.association(:gates).loaded?
      task.gates.select(&:pending?)
    else
      task.pending_gates
    end

    gates.map { |gate| BoardTaskResource.gate_payload(gate) }
  end

  # The task's CI story, newest first: what is still pending, what passed, what
  # failed, and what went stale because no provider verdict could be obtained.
  # `pending_gates` alone cannot say any of that — a gate leaves it the moment it
  # stops blocking, which is exactly when the outcome becomes interesting.
  typelize GATE_TYPE
  attribute :ci_gates do |task|
    task.gates
        .select(&:ci?)
        .sort_by(&:created_at)
        .reverse
        .first(CI_GATE_LIMIT)
        .map { |gate| BoardTaskResource.gate_payload(gate) }
  end
end
