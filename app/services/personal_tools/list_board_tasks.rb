# frozen_string_literal: true

module PersonalTools
  class ListBoardTasks < Base
    tool do
      display_name "List Board Tasks"
      description "List tasks on a project's board, optionally filtered by column or tag."
      audience :user
      tags :board
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :column_id, type: :integer, description: "Filter to a board column id."
      param :tag, type: :string, description: "Filter by tag."
    end

    LIMIT = 100

    def execute
      project = find_project!
      authorize!(project.board, :index?, policy: Web::Company::Projects::Board::TasksPolicy, project: project)
      board = project.board
      return error("This project has no board") unless board

      tasks = board.board_tasks.includes(:board_column, :assignee)
      tasks = tasks.where(board_column_id: params[:column_id]) if params[:column_id].present?
      tasks = tasks.with_tag(params[:tag]) if params[:tag].present?

      rows = tasks.limit(LIMIT).map do |t|
        { id: t.id, title: t.title, task_type: t.task_type, priority: t.priority,
          column: t.board_column&.name, column_id: t.board_column_id,
          assignee: t.assignee&.name, assignee_id: t.assignee_id, tags: t.tags }
      end
      payload = { project_id: project.id, tasks: rows }
      payload[:truncated] = true if tasks.count > LIMIT
      success(payload)
    end
  end
end
