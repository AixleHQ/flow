# frozen_string_literal: true

class TaskStatisticsService
  WorkflowBreakdown = Struct.new(
    :workflow_id, :workflow_name, :cost_cents, :total_tokens, :duration_seconds,
    keyword_init: true
  )

  GateStat = Struct.new(
    :id, :gate_type, :status, :created_at, :resolved_at, :duration_seconds,
    keyword_init: true
  )

  Result = Struct.new(
    :cost_totals, :token_totals, :time_totals,
    :gate_stats, :workflow_breakdowns,
    keyword_init: true
  )

  def initialize(task:)
    @task = task
  end

  def call
    agg = aggregate_workflow_runs
    workflow_breakdowns = build_workflow_breakdowns
    gate_stats = build_gate_stats

    Result.new(
      cost_totals: {
        total_cost_cents: agg[:total_cost_cents]
      },
      token_totals: {
        total_tokens: agg[:total_tokens]
      },
      time_totals: {
        total_duration_seconds: agg[:total_duration_seconds]
      },
      gate_stats:,
      workflow_breakdowns:
    )
  end

  private

  def aggregate_workflow_runs
    row = WorkflowRun
      .joins("LEFT JOIN step_runs ON step_runs.workflow_run_id = workflow_runs.id")
      .joins("LEFT JOIN usage_statistics ON usage_statistics.terminal_session_id = step_runs.terminal_session_id")
      .where(board_task_id: @task.id)
      .select(
        "COALESCE(SUM(usage_statistics.cost_cents), 0) AS total_cost_cents",
        "COALESCE(NULLIF(SUM(usage_statistics.input_tokens + usage_statistics.output_tokens + " \
        "usage_statistics.cache_write_tokens + usage_statistics.cache_read_tokens), 0), " \
        "SUM(usage_statistics.tokens), 0) AS total_tokens",
        "COALESCE(SUM(EXTRACT(EPOCH FROM (workflow_runs.completed_at - workflow_runs.started_at))::bigint) " \
        "FILTER (WHERE workflow_runs.completed_at IS NOT NULL AND workflow_runs.started_at IS NOT NULL), 0) AS total_duration_seconds"
      ).take

    {
      total_cost_cents: row.total_cost_cents.to_i,
      total_tokens: row.total_tokens.to_i,
      total_duration_seconds: row.total_duration_seconds.to_i
    }
  end

  def build_workflow_breakdowns
    rows = WorkflowRun
      .joins(:workflow)
      .joins("LEFT JOIN step_runs ON step_runs.workflow_run_id = workflow_runs.id")
      .joins("LEFT JOIN usage_statistics ON usage_statistics.terminal_session_id = step_runs.terminal_session_id")
      .where(board_task_id: @task.id)
      .group("workflows.id, workflows.name")
      .select(
        "workflows.id AS workflow_id",
        "workflows.name AS workflow_name",
        "COALESCE(SUM(usage_statistics.cost_cents), 0) AS cost_cents",
        "COALESCE(NULLIF(SUM(usage_statistics.input_tokens + usage_statistics.output_tokens + " \
        "usage_statistics.cache_write_tokens + usage_statistics.cache_read_tokens), 0), " \
        "SUM(usage_statistics.tokens), 0) AS total_tokens",
        "COALESCE(SUM(EXTRACT(EPOCH FROM (workflow_runs.completed_at - workflow_runs.started_at))::bigint) " \
        "FILTER (WHERE workflow_runs.completed_at IS NOT NULL AND workflow_runs.started_at IS NOT NULL), 0) AS duration_seconds"
      )
      .order("cost_cents DESC")

    rows.map do |row|
      WorkflowBreakdown.new(
        workflow_id: row.workflow_id,
        workflow_name: row.workflow_name,
        cost_cents: row.cost_cents.to_i,
        total_tokens: row.total_tokens.to_i,
        duration_seconds: row.duration_seconds.to_i
      )
    end
  end

  def build_gate_stats
    @task.gates.order(:created_at).map do |gate|
      resolved_at = gate.resolved? ? gate.resolved_at : nil
      duration = resolved_at ? (resolved_at - gate.created_at).round : nil

      GateStat.new(
        id: gate.id,
        gate_type: gate.gate_type,
        status: gate.status,
        created_at: gate.created_at,
        resolved_at: resolved_at,
        duration_seconds: duration
      )
    end
  end
end
