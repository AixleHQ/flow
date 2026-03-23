# frozen_string_literal: true

class WorkflowCostAnalyticsSerializer
  def initialize(result)
    @result = result
  end

  def as_json(*)
    {
      workflows: serialize_workflows,
      timeSeries: serialize_time_series,
      totals: serialize_totals
    }
  end

  private

  attr_reader :result

  def serialize_workflows
    result.workflows.map do |w|
      {
        workflowId: w.workflow_id,
        workflowName: w.workflow_name,
        totalCostCents: w.total_cost_cents,
        inputTokens: w.input_tokens,
        outputTokens: w.output_tokens,
        totalTokens: w.total_tokens,
        runCount: w.run_count,
        totalDurationSeconds: w.total_duration_seconds,
        avgDurationSeconds: w.avg_duration_seconds
      }
    end
  end

  def serialize_time_series
    result.time_series.map do |p|
      {
        date: p.date,
        costCents: p.cost_cents,
        totalTokens: p.total_tokens
      }
    end
  end

  def serialize_totals
    {
      totalCostCents: result.totals[:total_cost_cents],
      inputTokens: result.totals[:input_tokens],
      outputTokens: result.totals[:output_tokens],
      totalTokens: result.totals[:total_tokens],
      workflowCount: result.totals[:workflow_count],
      avgCostCentsPerWorkflow: result.totals[:avg_cost_cents_per_workflow]
    }
  end
end
