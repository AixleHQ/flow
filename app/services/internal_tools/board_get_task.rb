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
            description: TASK_ID_PARAM
          },
          task_number: {
            type: "integer",
            description: TASK_NUMBER_PARAM
          }
        }
      })
    end

    def execute
      require_workflow_context!
      board = BoardContextResolver.resolve(session)
      return error("No board available in current context") unless board
      task = find_task(board.board_tasks.includes(:workflow_runs, :gates), default_id: workflow_run&.board_task_id)
      return error(task_not_found) unless task

      success(BoardTaskResource.new(task, params: { snake_keys: true }).to_h.to_json)
    end
  end
end
