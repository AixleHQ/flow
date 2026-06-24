# frozen_string_literal: true

class TaskStatisticsResource < ApplicationResource
  attribute :cost_totals do |result|
    { totalCostCents: result.cost_totals[:total_cost_cents] }
  end

  attribute :token_totals do |result|
    { totalTokens: result.token_totals[:total_tokens] }
  end

  attribute :time_totals do |result|
    { totalDurationSeconds: result.time_totals[:total_duration_seconds] }
  end

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
