# frozen_string_literal: true

class TaskStatisticsSerializer
  def initialize(result)
    @result = result
  end

  def as_json(*)
    {
      costTotals: serialize_cost_totals,
      tokenTotals: serialize_token_totals,
      timeTotals: serialize_time_totals,
      waitStats: serialize_wait_stats,
      workflowBreakdowns: serialize_workflow_breakdowns
    }
  end

  private

  attr_reader :result

  def serialize_cost_totals
    {
      totalCostCents: result.cost_totals[:total_cost_cents]
    }
  end

  def serialize_token_totals
    {
      totalTokens: result.token_totals[:total_tokens]
    }
  end

  def serialize_time_totals
    {
      totalDurationSeconds: result.time_totals[:total_duration_seconds]
    }
  end

  def serialize_wait_stats
    result.wait_stats.map do |w|
      {
        id: w.id,
        waitType: w.wait_type,
        status: w.status,
        createdAt: w.created_at,
        resolvedAt: w.resolved_at,
        durationSeconds: w.duration_seconds
      }
    end
  end

  def serialize_workflow_breakdowns
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
