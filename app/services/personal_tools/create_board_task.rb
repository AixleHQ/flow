# frozen_string_literal: true

module PersonalTools
  class CreateBoardTask < Base
    tool do
      display_name "Create Board Task"
      description "Create a task on a project's board in the given column."
      audience :user
      tags :board
      param :project_id, type: :integer, description: "Project id.", required: true
      param :column_id, type: :integer, description: "Target column id (from list_board_columns).", required: true
      param :title, type: :string, description: "Task title.", required: true
      param :description, type: :string, description: "Task description (markdown)."
      param :task_type, type: :string, description: "Task type."
      param :priority, type: :string, description: "Task priority."
      param :assignee_id, type: :integer,
            description: "User id to assign the task to — must be a project member (see list_project_members)."
      param :tags, type: :array, description: "Task tags.", items: { type: "string" }
    end

    def execute
      project = find_project!
      authorize!(project.board, :create?, policy: Web::Company::Projects::Board::TasksPolicy, project: project)
      board = project.board
      return error("This project has no board") unless board

      column = board.board_columns.find_by(id: params[:column_id])
      return error("Column #{params[:column_id]} not found on this board") unless column

      task = TaskService.create(
        board: board,
        params: { board_column: column, title: params[:title], description: params[:description],
                  task_type: params[:task_type].presence || :not_specified,
                  priority: params[:priority].presence, assignee_id: params[:assignee_id].presence,
                  tags: params[:tags] || [] }.compact,
        actor: user
      )
      return error("Failed to create task: #{task.errors.full_messages.to_sentence}") unless task.persisted?

      success(id: task.id, title: task.title, column: column.name, column_id: column.id,
              assignee_id: task.assignee_id, position: task.position)
    end
  end
end
