# frozen_string_literal: true

class Web::Company::Projects::BoardsController < Web::Company::Projects::ApplicationController
  include BoardTaskDetail

  def show
    board = current_project.board

    if board && (legacy_task = legacy_linked_task(board))
      redirect_to company_project_board_path(current_project, n: legacy_task.number)
    elsif board
      render_board_page(board)
    else
      render_empty_board_page
    end
  end

  private

  # Which runs are waiting on a slot is one query for the whole page; asking it
  # per card would put a join behind every ticket on the board.
  def serialize_board_tasks(tasks)
    tasks = tasks.to_a
    recent = WorkflowRun.recent_by_task(tasks.map(&:id), limit: BoardTaskResource::RECENT_RUNS)
    waiting = WorkflowRun.waiting_for_slot_ids(recent.values.flatten.map(&:id))
    tasks.map do |task|
      BoardTaskResource.new(task, params: { waiting_runs: waiting, recent_runs: recent, without_description: true }).to_h
    end
  end

  def render_board_page(board)
    task = params[:n].present? ? find_board_task(board, params[:n]) : nil

    render inertia: "Projects/Board/BoardPage", props: {
      board: -> { BoardResource.new(board).to_h },
      **board_options_props(board),
      # Only the first page of each column. The column pulls its later pages from
      # Api::V1::Projects::Board::TasksController as it is scrolled, so this payload
      # stays the same size whether the board holds fifty tasks or five thousand.
      tasks: -> {
        board.board_tasks
             .active
             .first_per_column(BoardTask::PAGE_SIZE)
             .with_card_counts
             .includes(:assignee, :assignee_team, :gates)
             .in_board_order.then { |tasks| serialize_board_tasks(tasks) }
      },
      tasks_page_size: BoardTask::PAGE_SIZE,
      workflows: -> { current_project.workflows.not_drafts.order(:name).map { |w| BoardWorkflowResource.new(w).to_h } },
      view_presets: -> {
        board.board_view_presets.visible_to(current_user).order(:name)
             .map { |p| BoardViewPresetResource.new(p).to_h }
      },
      current_user_id: -> { current_user.id },
      cable_stream: -> { inertia_cable_stream(board) },
      recent_activities: InertiaRails.defer {
        board.board_activities.includes(:actor, :board_task)
             .order(created_at: :desc).limit(20)
             .map { |a| BoardActivityResource.new(a, params: { without_changes: true }).to_h }
      },
      **task_detail_props(task)
    }
  end

  def render_empty_board_page
    render inertia: "Projects/Board/BoardPage", props: {
      board: nil,
      board_presets: -> { BoardPresets.all.map { |p| BoardPresetResource.new(p).to_h } },
      columns: [],
      tasks: [],
      tasks_page_size: BoardTask::PAGE_SIZE,
      board_tags: [],
      epics: [],
      members: [],
      teams: [],
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

  # `?task=` carried the global task id before tasks were numbered per board, and
  # links with it are still around, so it keeps meaning the id.
  def legacy_linked_task(board)
    return if params[:task].blank? || params[:n].present?

    board.board_tasks.find_by(id: params[:task])
  end
end
