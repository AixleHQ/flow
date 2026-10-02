# frozen_string_literal: true

module InternalTools
  class BoardGetTask < Base
    tool do
      display_name "Board Get Task"
      description "Return full details for a board task, by task_id or by task_number (the #N people see " \
                  "on the board). Defaults to the workflow's bound board task when both are omitted."
      tags :board
      inject_when :workflow_step_session
      input_schema({
        type: "object",
        required: [],
        properties: {
          task_id: {
            type: "integer",
            description: "Internal board task id (the `id` field), not the #N shown on the board. " \
                         "Optional when the workflow run is already attached to a board task."
          },
          task_number: {
            type: "integer",
            description: "The task's number on this board — what a person means by \"#12\". " \
                         "Give either this or task_id, not both."
          }
        }
      })
    end

    def execute
      require_workflow_context!
      board = BoardContextResolver.resolve(session)
      return error("No board available in current context") unless board
      return error("Pass either task_id or task_number, not both") if params[:task_id] && params[:task_number]

      lookup = task_lookup
      return error("task_id or task_number is required") unless lookup

      task = board.board_tasks
                  .includes(:workflow_runs, :gates)
                  .find_by(lookup)
      return error("Task not found on this board") unless task

      success(BoardTaskResource.new(task, params: { snake_keys: true }).to_h.to_json)
    end

    private

    def task_lookup
      if params[:task_id] then { id: params[:task_id] }
      elsif params[:task_number] then { number: params[:task_number] }
      elsif workflow_run&.board_task_id then { id: workflow_run.board_task_id }
      end
    end
  end
end
