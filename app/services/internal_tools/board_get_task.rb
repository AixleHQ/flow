# frozen_string_literal: true

module InternalTools
  class BoardGetTask < Base
    tool do
      display_name "Board Get Task"
      description "Return full details for a board task. Defaults to the workflow's bound board task when task_id is omitted."
      tags :board
      inject_when :workflow_step_session
      input_schema({
        type: "object",
        required: [],
        properties: {
          task_id: {
            type: "integer",
            description: "Board task ID. Optional when the workflow run is already attached to a board task."
          }
        }
      })
    end

    def execute
      require_workflow_context!
      board = BoardContextResolver.resolve(session)
      return error("No board available in current context") unless board

      task_id = params[:task_id] || workflow_run&.board_task_id
      return error("task_id is required") unless task_id

      task = board.board_tasks
                  .includes(:task_comments, :child_tasks, :task_assets, :workflow_runs, :pending_gates)
                  .find_by(id: task_id)
      return error("Task not found on this board") unless task

      success(BoardTaskResource.new(task).to_h.to_json)
    end
  end
end
