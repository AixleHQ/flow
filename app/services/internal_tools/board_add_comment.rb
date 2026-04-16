# frozen_string_literal: true

module InternalTools
  class BoardAddComment < Base
    def execute
      require_workflow_context!
      board = BoardContextResolver.resolve(session)
      return error("No board available in current context") unless board

      task = board.board_tasks.find_by(id: params[:task_id])
      return error("Task not found on this board") unless task

      author = resolve_actor(task)
      return error("Cannot determine comment author") unless author

      comment = task.task_comments.create!(
        body: params[:body],
        author: author,
        author_type: :agent,
        tags: params[:tags] || []
      )

      board.touch

      success({
        id: comment.id,
        body: comment.body.truncate(200),
        tags: comment.tags
      }.to_json)
    end

    private

    def resolve_actor(task)
      task.assignee || workflow_run&.user
    end
  end
end
