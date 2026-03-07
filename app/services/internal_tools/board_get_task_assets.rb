# frozen_string_literal: true

module InternalTools
  class BoardGetTaskAssets < Base
    def execute
      require_workflow_context!
      board = BoardContextResolver.resolve(session)
      return error("No board available in current context") unless board

      task = board.board_tasks.find_by(id: params[:task_id])
      return error("Task not found on this board") unless task

      assets = task.task_assets.includes(:author).order(created_at: :desc)
      assets = assets.with_tag(params[:tag]) if params[:tag].present?

      result = assets.map { |a| TaskAssetSerializer.new(a).as_json }
      success(result.to_json)
    end
  end
end
