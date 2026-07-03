# frozen_string_literal: true

module PersonalTools
  class MoveBoardTask < Base
    tool do
      display_name "Move Board Task"
      description "Move a board task to another column (optionally to a specific position)."
      audience :user
      tags :board
      param :project_id, type: :integer, description: "Project id.", required: true
      param :task_id, type: :integer, description: "Board task id.", required: true
      param :column_id, type: :integer, description: "Destination column id.", required: true
      param :position, type: :integer, description: "Optional 0-based position within the column."
    end

    def execute
      project = find_project!
      authorize!(project.board, :move?, policy: Web::Company::Projects::Board::TasksPolicy, project: project)
      board = project.board
      task = board&.board_tasks&.find_by(id: params[:task_id])
      return error("Task not found on this project's board") unless task

      column = board.board_columns.find_by(id: params[:column_id])
      return error("Column #{params[:column_id]} not found on this board") unless column

      from = task.board_column&.name
      TaskService.move(task: task, to_column: column, position: params[:position], actor: user, actor_type: :human)
      success(id: task.id, title: task.title, from_column: from, to_column: column.name)
    end
  end
end
