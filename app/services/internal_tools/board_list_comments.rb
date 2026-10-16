# frozen_string_literal: true

module InternalTools
  class BoardListComments < Base
    tool do
      display_name "Board List Comments"
      description "Page through a task's comments, newest first. Bodies are previews; read a truncated " \
                  "comment in full with board_get_comment. Follow has_more and offset to inspect older decisions."
      tags :board
      inject_when :workflow_step_session
      read_only
      param :task_id, type: :integer, description: "Internal task ID on the current board.", required: true
      param :limit, type: :integer, description: "Comments per page (default 25, maximum 100)."
      param :offset, type: :integer, description: "Comments to skip (default 0)."
      param :tag, type: :string, description: "Filter by comment tag."
      param :author_type, type: :string, enum: %w[human user agent system],
                         description: "Filter by author type; user is a compatible alias for human."
    end

    def execute
      require_workflow_context!
      board = BoardContextResolver.resolve(session)
      task = board&.board_tasks&.find_by(id: params[:task_id])
      return error("Task not found on this board") unless task

      scope = task.task_comments
      scope = scope.with_tag(params[:tag]) if params[:tag].present?
      author_type = params[:author_type] == "user" ? "human" : params[:author_type]
      scope = scope.by_author_type(author_type) if author_type.present?
      total = scope.count
      limit = params[:limit].present? ? params[:limit].to_i.clamp(1, 100) : 25
      offset = [ params[:offset].to_i, 0 ].max
      comments = scope.includes(:author).order(created_at: :desc, id: :desc).limit(limit).offset(offset).map do |comment|
        TaskCommentResource.new(comment, params: { snake_keys: true }).to_h.merge(
          "body" => comment.body.truncate(400), "body_length" => comment.body.length,
          "body_truncated" => comment.body.length > 400
        )
      end
      success({ comments: comments, total: total, limit: limit, offset: offset,
                has_more: offset + comments.size < total }.to_json)
    end
  end
end
