# frozen_string_literal: true

class WorkflowCostAnalyticsService
  include TaskFilterable
  PERIOD_DAYS = {
    "7d" => 7,
    "30d" => 30,
    "90d" => 90,
    "1y" => 365
  }.freeze

  DATE_TRUNC_GROUP_SQL = {
    "day"   => Arel.sql("DATE_TRUNC('day', workflow_runs.created_at)"),
    "week"  => Arel.sql("DATE_TRUNC('week', workflow_runs.created_at)"),
    "month" => Arel.sql("DATE_TRUNC('month', workflow_runs.created_at)")
  }.freeze

  DATE_TRUNC_ORDER_SQL = {
    "day"   => Arel.sql("DATE_TRUNC('day', workflow_runs.created_at) ASC"),
    "week"  => Arel.sql("DATE_TRUNC('week', workflow_runs.created_at) ASC"),
    "month" => Arel.sql("DATE_TRUNC('month', workflow_runs.created_at) ASC")
  }.freeze

  DATE_TRUNC_SELECT_SQL = {
    "day"   => Arel.sql("DATE_TRUNC('day', workflow_runs.created_at) AS period_date"),
    "week"  => Arel.sql("DATE_TRUNC('week', workflow_runs.created_at) AS period_date"),
    "month" => Arel.sql("DATE_TRUNC('month', workflow_runs.created_at) AS period_date")
  }.freeze

  WorkflowRow = Struct.new(
    :workflow_id, :workflow_name,
    :total_cost_cents, :input_tokens, :output_tokens, :total_tokens,
    :run_count, :total_duration_seconds, :avg_duration_seconds,
    keyword_init: true
  )

  TimeSeriesPoint = Struct.new(:date, :cost_cents, :total_tokens, keyword_init: true)

  Result = Struct.new(:workflows, :time_series, :totals, keyword_init: true)

  def initialize(project:, user:, scope:, period:, tags: nil, task_type: nil)
    @project = project
    @user = user
    @scope = scope.to_s
    @period = period.to_s
    @days = PERIOD_DAYS.fetch(@period, 30)
    @since = @days.days.ago
    @tags = Array.wrap(tags).reject(&:blank?)
    @task_type = task_type.presence
  end

  def call
    runs = base_workflow_runs

    workflow_rows = build_workflow_breakdown(runs)
    time_series = build_time_series(runs)
    totals = aggregate_totals(workflow_rows)

    Result.new(workflows: workflow_rows, time_series:, totals:)
  end

  private

  attr_reader :project, :user, :scope, :since, :days, :period, :tags, :task_type

  def base_workflow_runs
    runs = case scope
           when "user"
             WorkflowRun.for_user_in_project(project, user, since)
           else
             WorkflowRun.for_project_in_period(project, since)
           end

    if tags.present? || task_type.present?
      runs = runs.where(board_task_id: filtered_board_tasks.select(:id))
    end

    runs
  end

  def build_workflow_breakdown(runs)
    rows = runs
      .joins(:workflow)
      .joins(
        "LEFT JOIN step_runs ON step_runs.workflow_run_id = workflow_runs.id"
      )
      .joins(
        "LEFT JOIN usage_statistics ON usage_statistics.terminal_session_id = step_runs.terminal_session_id"
      )
      .group("workflows.id, workflows.name")
      .select(
        "workflows.id AS workflow_id",
        "workflows.name AS workflow_name",
        "COUNT(DISTINCT workflow_runs.id) AS run_count",
        "COALESCE(SUM(usage_statistics.cost_cents), 0) AS total_cost_cents",
        "COALESCE(SUM(usage_statistics.input_tokens), 0) AS input_tokens",
        "COALESCE(SUM(usage_statistics.output_tokens), 0) AS output_tokens",
        "COALESCE(NULLIF(SUM(usage_statistics.input_tokens + usage_statistics.output_tokens + " \
        "usage_statistics.cache_write_tokens + usage_statistics.cache_read_tokens), 0), " \
        "SUM(usage_statistics.tokens), 0) AS total_tokens",
        "COALESCE(SUM(EXTRACT(EPOCH FROM (workflow_runs.completed_at - workflow_runs.started_at))::bigint), 0) AS total_duration_seconds",
        "COALESCE(AVG(EXTRACT(EPOCH FROM (workflow_runs.completed_at - workflow_runs.started_at))::bigint) " \
        "FILTER (WHERE workflow_runs.completed_at IS NOT NULL AND workflow_runs.started_at IS NOT NULL), 0) AS avg_duration_seconds"
      )
      .order("total_cost_cents DESC")

    rows.map do |row|
      WorkflowRow.new(
        workflow_id: row.workflow_id,
        workflow_name: row.workflow_name,
        total_cost_cents: row.total_cost_cents.to_i,
        input_tokens: row.input_tokens.to_i,
        output_tokens: row.output_tokens.to_i,
        total_tokens: row.total_tokens.to_i,
        run_count: row.run_count.to_i,
        total_duration_seconds: row.total_duration_seconds.to_i,
        avg_duration_seconds: row.avg_duration_seconds.to_i
      )
    end
  end

  def build_time_series(runs)
    trunc_key = time_series_trunc

    points = runs
      .joins(
        "LEFT JOIN step_runs ON step_runs.workflow_run_id = workflow_runs.id"
      )
      .joins(
        "LEFT JOIN usage_statistics ON usage_statistics.terminal_session_id = step_runs.terminal_session_id"
      )
      .group(DATE_TRUNC_GROUP_SQL.fetch(trunc_key, DATE_TRUNC_GROUP_SQL["day"]))
      .order(DATE_TRUNC_ORDER_SQL.fetch(trunc_key, DATE_TRUNC_ORDER_SQL["day"]))
      .select(
        DATE_TRUNC_SELECT_SQL.fetch(trunc_key, DATE_TRUNC_SELECT_SQL["day"]),
        "COALESCE(SUM(usage_statistics.cost_cents), 0) AS cost_cents",
        "COALESCE(NULLIF(SUM(usage_statistics.input_tokens + usage_statistics.output_tokens + " \
        "usage_statistics.cache_write_tokens + usage_statistics.cache_read_tokens), 0), " \
        "SUM(usage_statistics.tokens), 0) AS total_tokens"
      )

    points.map do |point|
      TimeSeriesPoint.new(
        date: point.period_date.to_date.iso8601,
        cost_cents: point.cost_cents.to_i,
        total_tokens: point.total_tokens.to_i
      )
    end
  end

  def aggregate_totals(workflow_rows)
    {
      total_cost_cents: workflow_rows.sum(&:total_cost_cents),
      input_tokens: workflow_rows.sum(&:input_tokens),
      output_tokens: workflow_rows.sum(&:output_tokens),
      total_tokens: workflow_rows.sum(&:total_tokens),
      workflow_count: workflow_rows.size,
      avg_cost_cents_per_workflow: workflow_rows.empty? ? 0 : (workflow_rows.sum(&:total_cost_cents).to_f / workflow_rows.size).round
    }
  end

  def time_series_trunc
    case period
    when "7d" then "day"
    when "30d" then "day"
    when "90d" then "week"
    when "1y" then "month"
    else "day"
    end
  end
end
