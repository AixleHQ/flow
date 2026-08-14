# frozen_string_literal: true

class TaskStatisticsResource < ApplicationResource
  typelize "{ totalCostCents: number }"
  attribute :cost_totals do |result|
    { totalCostCents: result.cost_totals[:total_cost_cents] }
  end

  typelize "{ totalTokens: number }"
  attribute :token_totals do |result|
    { totalTokens: result.token_totals[:total_tokens] }
  end

  typelize "{ totalDurationSeconds: number }"
  attribute :time_totals do |result|
    { totalDurationSeconds: result.time_totals[:total_duration_seconds] }
  end

  # `stale` is the third terminal state a CI gate can end in (reconciliation gave up
  # without a provider verdict) — the Analytics Waits panel counts it, so the
  # generated type has to be able to express it.
  typelize "Array<{ id: number; gateType: \"github_checks_completed\" | \"github_workflow_completed\" | \"gitlab_pipeline_completed\"; status: \"pending\" | \"resolved\" | \"stale\"; createdAt: string; resolvedAt: string | null; durationSeconds: number | null }>"
  attribute :gate_stats do |result|
    result.gate_stats.map do |w|
      {
        id: w.id,
        gateType: w.gate_type,
        status: w.status,
        createdAt: w.created_at,
        resolvedAt: w.resolved_at,
        durationSeconds: w.duration_seconds
      }
    end
  end

  typelize "Array<{ workflowId: number; workflowName: string; costCents: number; totalTokens: number; durationSeconds: number }>"
  attribute :workflow_breakdowns do |result|
    result.workflow_breakdowns.map do |b|
      {
        workflowId: b.workflow_id,
        workflowName: b.workflow_name,
        costCents: b.cost_cents,
        totalTokens: b.total_tokens,
        durationSeconds: b.duration_seconds
      }
    end
  end
end
