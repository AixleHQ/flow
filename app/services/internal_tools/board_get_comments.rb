# frozen_string_literal: true

module InternalTools
  class BoardGetComments < Base
    def execute
      require_workflow_context!
      board = BoardContextResolver.resolve(session)
      return error("No board available in current context") unless board

      task = board.board_tasks.find_by(id: params[:task_id])
      return error("Task not found on this board") unless task

      comments = task.task_comments.includes(:author).order(created_at: :desc)
      comments = comments.with_tag(params[:tag]) if params[:tag].present?
      comments = comments.by_author_type(params[:author_type]) if params[:author_type].present?

      result = comments.map { |c| TaskCommentResource.new(c).to_h }
      success(result.to_json)
    end
  end
end
