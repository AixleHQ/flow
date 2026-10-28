# frozen_string_literal: true

module InternalTools
  class BoardGetTaskAssets < Base
    tool do
      display_name "Board Get Task Assets"
      description "List files attached to a board task, optionally filtered by tag."
      tags :board
      inject_when :workflow_step_session
      input_schema({
        type: "object",
        required: [],
        properties: {
          tag: {
            type: "string",
            description: "Optional tag filter"
          },
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

      task = find_task(board.board_tasks)
      return error(task_not_found) unless task

      assets = task.task_assets.includes(:author).order(created_at: :desc)
      assets = assets.with_tag(params[:tag]) if params[:tag].present?

      result = assets.map { |a| TaskAssetResource.new(a, params: { snake_keys: true }).to_h }
      success(result.to_json)
    end
  end
end
