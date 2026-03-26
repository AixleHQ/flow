# frozen_string_literal: true

class ProjectAnalyticsService
  PERIOD_DAYS = {
    "7d" => 7,
    "30d" => 30,
    "90d" => 90,
    "1y" => 365
  }.freeze

  Result = Struct.new(
    :total_sessions, :total_cost_cents, :total_tokens,
    :avg_cost_cents_per_session, :workflows_run,
    keyword_init: true
  )

  def initialize(project:, user:, scope:, period:, tags: nil, task_type: nil)
    @project = project
    @user = user
    @scope = scope.to_s
    @since = PERIOD_DAYS.fetch(period.to_s, 30).days.ago
    @tags = Array(tags).presence
    @task_type = task_type.presence
  end

  def call
    sessions = base_sessions
    stats = usage_stats_for(sessions)

    total_sessions = sessions.count
    total_cost_cents = stats[:cost_cents]
    total_tokens = stats[:tokens]
    avg_cost = total_sessions.positive? ? (total_cost_cents.to_f / total_sessions).round : 0

    Result.new(
      total_sessions:,
      total_cost_cents:,
      total_tokens:,
      avg_cost_cents_per_session: avg_cost,
      workflows_run: base_workflow_runs.count
    )
  end

  private

  attr_reader :project, :user, :scope, :since, :tags, :task_type

  def base_sessions
    scope_sessions.where(created_at: since..).then { |s| apply_task_filters(s) }
  end

  def scope_sessions
    case scope
    when "user"
      project.terminal_sessions.where(user:)
    else
      project.terminal_sessions
    end
  end

  def apply_task_filters(sessions)
    return sessions unless tags.present? || task_type.present?

    board_tasks = project.board&.board_tasks || BoardTask.none
    board_tasks = board_tasks.tags_overlap(tags) if tags.present?
    board_tasks = board_tasks.where(task_type: task_type) if task_type.present?

    sessions.where(
      id: StepRun.where(workflow_run_id: WorkflowRun.where(board_task_id: board_tasks.select(:id))).select(:terminal_session_id)
    )
  end

  def usage_stats_for(sessions)
    row = UsageStatistic
      .where(terminal_session_id: sessions.select(:id))
      .pick(
        Arel.sql("COALESCE(SUM(cost_cents), 0)"),
        Arel.sql("COALESCE(NULLIF(SUM(input_tokens + output_tokens + cache_write_tokens + cache_read_tokens), 0), SUM(tokens), 0)")
      )
    { cost_cents: row[0].to_i, tokens: row[1].to_i }
  end

  def base_workflow_runs
    runs = case scope
           when "user"
             project.workflow_runs.where(user:, created_at: since..)
           else
             project.workflow_runs.where(created_at: since..)
           end
    return runs unless tags.present? || task_type.present?

    board_tasks = project.board&.board_tasks || BoardTask.none
    board_tasks = board_tasks.tags_overlap(tags) if tags.present?
    board_tasks = board_tasks.where(task_type: task_type) if task_type.present?

    runs.where(board_task_id: board_tasks.select(:id))
  end
end
