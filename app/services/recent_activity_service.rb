# frozen_string_literal: true

class RecentActivityService
  ActivityItem = Struct.new(
    :event_type, :description, :actor_name, :actor_type, :occurred_at, :metadata,
    keyword_init: true
  )

  BOARD_FETCH_LIMIT = 150
  SESSION_FETCH_LIMIT = 75
  WORKFLOW_FETCH_LIMIT = 75

  def initialize(company, page: 1, per_page: 20)
    @company = company
    @page = [ page.to_i, 1 ].max
    @per_page = per_page.to_i.clamp(1, 100)
  end

  def call
    items = (board_activity_items + session_items + workflow_items)
      .sort_by { |i| -i.occurred_at.to_i }

    total = items.size
    offset = (@page - 1) * @per_page
    paginated = items[offset, @per_page] || []

    { activities: paginated.map(&:to_h), total:, page: @page, per_page: @per_page }
  end

  private

  attr_reader :company

  def board_ids
    @board_ids ||= Board.joins(:project).where(projects: { company_id: company.id }).pluck(:id)
  end

  def board_activity_items
    return [] if board_ids.empty?

    BoardActivity
      .where(board_id: board_ids)
      .includes(:actor, :board_task)
      .order(created_at: :desc)
      .limit(BOARD_FETCH_LIMIT)
      .map { |a| build_board_item(a) }
  end

  def session_items
    TerminalSession
      .joins(:user)
      .where(users: { company_id: company.id })
      .where(session_type: "agent_session")
      .order(created_at: :desc)
      .limit(SESSION_FETCH_LIMIT)
      .map { |s| build_session_item(s) }
  end

  def workflow_items
    WorkflowRun
      .joins(:project, :workflow)
      .joins(:user)
      .where(projects: { company_id: company.id })
      .order(created_at: :desc)
      .limit(WORKFLOW_FETCH_LIMIT)
      .map { |r| build_workflow_item(r) }
  end

  def build_board_item(activity)
    task_title = activity.board_task&.title ||
      activity.metadata&.dig("task_title") ||
      "a task"

    description = case activity.event_type
    when "task_created"          then "Task \"#{task_title}\" created"
    when "task_moved"            then "Task \"#{task_title}\" moved to #{activity.metadata&.dig("to_column") || "new column"}"
    when "task_updated"          then "Task \"#{task_title}\" updated"
    when "task_deleted"          then "Task \"#{task_title}\" deleted"
    when "comment_added"         then "Comment added on \"#{task_title}\""
    when "asset_attached"        then "Asset attached to \"#{task_title}\""
    when "workflow_started"      then "Workflow started for \"#{task_title}\""
    when "workflow_completed"    then "Workflow completed for \"#{task_title}\""
    when "workflow_failed"       then "Workflow failed for \"#{task_title}\""
    when "human_help_requested"  then "Human help requested for \"#{task_title}\""
    else                              "Activity on \"#{task_title}\""
    end

    ActivityItem.new(
      event_type: activity.event_type,
      description:,
      actor_name: activity.actor&.name || "Unknown",
      actor_type: activity.actor_type,
      occurred_at: activity.created_at,
      metadata: activity.metadata
    )
  end

  def build_session_item(session)
    agent_label = session.agent_type || "agent"

    event_type, description = case session.state
    when "running"  then [ "session_started",   "Session started with #{agent_label}" ]
    when "finished" then [ "session_completed",  "Session completed with #{agent_label}" ]
    when "failed"   then [ "session_failed",     "Session failed with #{agent_label}" ]
    else                 [ "session_#{session.state}", "Session #{session.state} with #{agent_label}" ]
    end

    ActivityItem.new(
      event_type:,
      description:,
      actor_name: session.user&.name || "Unknown",
      actor_type: "human",
      occurred_at: session.created_at,
      metadata: {}
    )
  end

  def build_workflow_item(run)
    workflow_name = run.workflow&.name || "Deleted Workflow"

    event_type, description = case run.state
    when "pending"   then [ "workflow_triggered",  "Workflow \"#{workflow_name}\" queued" ]
    when "running"   then [ "workflow_triggered",  "Workflow \"#{workflow_name}\" running" ]
    when "completed" then [ "workflow_completed",  "Workflow \"#{workflow_name}\" completed" ]
    when "failed"    then [ "workflow_failed",     "Workflow \"#{workflow_name}\" failed" ]
    when "cancelled" then [ "workflow_cancelled",  "Workflow \"#{workflow_name}\" cancelled" ]
    else                  [ "workflow_#{run.state}", "Workflow \"#{workflow_name}\" #{run.state}" ]
    end

    ActivityItem.new(
      event_type:,
      description:,
      actor_name: run.user&.name || "Unknown",
      actor_type: "human",
      occurred_at: run.created_at,
      metadata: {}
    )
  end
end
