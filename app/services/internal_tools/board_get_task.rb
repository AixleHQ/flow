# frozen_string_literal: true

module InternalTools
  class BoardGetTask < Base
    def execute
      require_workflow_context!
      board = BoardContextResolver.resolve(session)
      return error("No board available in current context") unless board

      task_id = params[:task_id] || workflow_run&.board_task_id
      return error("task_id is required") unless task_id

      task = board.board_tasks.find_by(id: task_id)
      return error("Task not found on this board") unless task

      success(BoardTaskResource.new(task).to_h.to_json)
    end
  end
end
