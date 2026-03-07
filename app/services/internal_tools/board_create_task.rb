# frozen_string_literal: true

module InternalTools
  class BoardCreateTask < Base
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
