# frozen_string_literal: true

module InternalTools
  class BoardCreateTask < Base
    tool do
      display_name "Board Create Task"
      description "Create a new board task in the current board, optionally targeting a specific column."
      tags :board
      inject_when :workflow_step_session
      input_schema({
        type: "object",
        required: %w[title],
        properties: {
          tags: {
            type: "array",
            items: {
              type: "string"
            },
            description: "Optional task tags"
          },
          title: {
            type: "string",
            description: "Task title"
          },
          task_type: {
            type: "string",
            description: "Task type"
          },
          column_name: {
            type: "string",
            description: "Target column name. Defaults to the first column."
          },
          description: {
            type: "string",
            description: "Task description"
          }
        }
      })
    end

    def execute
      require_workflow_context!
      board = BoardContextResolver.resolve(session)
      return error("No board available in current context") unless board

      column = if params[:column_name].present?
                 board.board_columns.find_by(name: params[:column_name])
      else
                 board.board_columns.order(:position).first
      end
      return error("Column '#{params[:column_name]}' not found") unless column

      task = board.board_tasks.create!(
        board_column: column,
        title: params[:title],
        description: params[:description],
        task_type: params[:task_type] || :not_specified,
        tags: params[:tags] || []
      )

      success({
        id: task.id,
        title: task.title,
        column: column.name,
        position: task.position
      }.to_json)
    end
  end
end
