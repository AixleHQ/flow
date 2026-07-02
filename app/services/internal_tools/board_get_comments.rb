# frozen_string_literal: true

module InternalTools
  class BoardGetComments < Base
    tool do
      display_name "Board Get Comments"
      description "List comments for a task on the current board with optional tag or author-type filters."
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
          },
          author_type: {
            enum: %w[user agent],
            type: "string",
            description: "Optional author type filter"
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

      comments = task.task_comments.includes(:author).order(created_at: :desc)
      comments = comments.with_tag(params[:tag]) if params[:tag].present?
      comments = comments.by_author_type(params[:author_type]) if params[:author_type].present?

      result = comments.map { |c| TaskCommentResource.new(c).to_h }
      success(result.to_json)
    end
  end
end
