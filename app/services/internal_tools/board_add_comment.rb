# frozen_string_literal: true

module InternalTools
  class BoardAddComment < Base
    tool do
      display_name "Board Add Comment"
      description "Add an agent comment to a task on the current board. Markdown is supported in the body field (bold, italic, code blocks, lists, links, tables, etc.)."
      tags :board
      inject_when :workflow_step_session
      input_schema({
        type: "object",
        required: %w[body],
        properties: {
          body: {
            type: "string",
            description: "Comment body. Markdown is supported (e.g. **bold**, `code`, lists, headings, links)."
          },
          tags: {
            type: "array",
            items: {
              type: "string"
            },
            description: "Optional comment tags"
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
