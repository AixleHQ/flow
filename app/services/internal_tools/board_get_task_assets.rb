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
        required: %w[task_id],
        properties: {
          tag: {
            type: "string",
            description: "Optional tag filter"
          },
          task_id: {
            type: "integer",
            description: "Board task ID"
          }
        }
      })
    end

    def execute
      require_workflow_context!
      board = BoardContextResolver.resolve(session)
      return error("No board available in current context") unless board

      task = board.board_tasks.find_by(id: params[:task_id])
      return error("Task not found on this board") unless task

      assets = task.task_assets.includes(:author).order(created_at: :desc)
      assets = assets.with_tag(params[:tag]) if params[:tag].present?

      result = assets.map { |a| TaskAssetResource.new(a, params: { snake_keys: true }).to_h }
      success(result.to_json)
    end
  end
end
