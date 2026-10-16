# frozen_string_literal: true

module InternalTools
  class BoardGetComment < Base
    tool do
      display_name "Board Get Comment"
      description "Read one complete comment, without preview truncation, from a task on the current board."
      tags :board
      inject_when :workflow_step_session
      read_only
      param :task_id, type: :integer, description: "Internal task ID on the current board.", required: true
      param :comment_id, type: :integer, description: "Comment ID from board_list_comments.", required: true
    end

    def execute
      require_workflow_context!
      board = BoardContextResolver.resolve(session)
      task = board&.board_tasks&.find_by(id: params[:task_id])
      comment = task&.task_comments&.includes(:author)&.find_by(id: params[:comment_id])
      return error("Comment not found on this task and board") unless comment

      success(TaskCommentResource.new(comment, params: { snake_keys: true }).to_h.to_json)
    end
  end
end
