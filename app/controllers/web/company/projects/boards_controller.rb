# frozen_string_literal: true

class Web::Company::Projects::BoardsController < Web::Company::Projects::ApplicationController
  def show
    board = current_project.board

    if board
      render_board_page(board)
    else
      render_empty_board_page
    end
  end

  private

  def render_board_page(board)
    task = params[:task].present? ? find_task(board) : nil

    render inertia: "Projects/Board/BoardPage", props: {
      board: -> { BoardResource.new(board).to_h },
      columns: -> {
        board.board_columns.includes(column_workflow_binding: :workflow)
             .order(:position).map { |c| BoardColumnResource.new(c).to_h }
      },
      tasks: -> {
        board.board_tasks
             .includes(:assignee, :child_tasks, :task_comments, :task_assets, :workflow_runs, :pending_task_waits)
             .order(:position).map { |t| BoardTaskResource.new(t).to_h }
      },
      members: -> { current_project.member_users.map { |u| BoardMemberResource.new(u).to_h } },
      workflows: -> { current_project.workflows.order(:name).map { |w| BoardWorkflowResource.new(w).to_h } },
      view_presets: -> {
        board.board_view_presets.visible_to(current_user).order(:name)
             .map { |p| BoardViewPresetResource.new(p).to_h }
      },
      current_user_id: -> { current_user.id },
      cable_stream: -> { inertia_cable_stream(board) },
      recent_activities: InertiaRails.defer {
        board.board_activities.includes(:actor, :board_task)
             .order(created_at: :desc).limit(20)
             .map { |a| BoardActivityResource.new(a).to_h }
      },
      selected_task: -> { task ? BoardTaskResource.new(task).to_h : nil },
      task_comments: -> {
        next [] unless task
        task.task_comments.includes(:author).order(created_at: :desc)
            .map { |c| TaskCommentResource.new(c).to_h }
      },
      task_assets: -> {
        next [] unless task
        task.task_assets.order(created_at: :desc).map { |a| TaskAssetResource.new(a).to_h }
      },
      task_activities: -> {
        next [] unless task
        task.board_activities.includes(:actor, :board_task).order(created_at: :desc)
            .map { |a| BoardActivityResource.new(a).to_h }
      },
      task_workflow_runs: -> {
        next [] unless task
        task.workflow_runs.includes(:workflow).order(created_at: :desc)
            .map { |r| TaskWorkflowRunResource.new(r).to_h }
      },
      task_statistics: -> {
        next nil unless task
        TaskStatisticsResource.new(TaskStatisticsService.new(task: task).call).to_h
      }
    }
  end

  def render_empty_board_page
    render inertia: "Projects/Board/BoardPage", props: {
      board: nil,
      board_presets: -> { BoardPresets.all.map { |p| BoardPresetResource.new(p).to_h } },
      columns: [],
      tasks: [],
      members: [],
      workflows: [],
      view_presets: [],
      current_user_id: -> { current_user.id },
      recent_activities: [],
      selected_task: nil,
      task_comments: [],
      task_assets: [],
      task_activities: [],
      task_workflow_runs: [],
      task_statistics: nil
    }
  end

  def find_task(board)
    board.board_tasks
         .includes(:assignee, :child_tasks, :task_comments, :task_assets, :workflow_runs, :pending_task_waits)
         .find_by(id: params[:task])
  end
end
