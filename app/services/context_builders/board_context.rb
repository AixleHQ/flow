# frozen_string_literal: true

module ContextBuilders
  class BoardContext < Base
    def applicable?
      board_task.present?
    end

    def build
      [
        section(
          tag: "board-context",
          priority: :important,
          content: build_board_context,
          position_hint: :top
        )
      ]
    end

    private

    def build_board_context
      task = board_task
      board = task.board
      column = task.board_column

      lines = []
      lines << "## Board Task Context"
      lines << ""
      lines << "You are working on a specific task from the project board."
      lines << ""
      lines << "- **Board:** #{board.name}"
      lines << "- **Task:** #{task.title} (id: #{task.id})"
      lines << "- **Column:** #{column.name}" if column
      lines << "- **Priority:** #{task.priority}" if task.priority.present?
      lines << "- **Description:** #{task.description.truncate(500)}" if task.description.present?
      lines << "- **Tags:** #{task.tags.join(', ')}" if task.tags.present?

      comments = task.task_comments.recent.includes(:author).limit(5)
      if comments.any?
        lines << ""
        lines << "### Recent Comments"
        comments.each do |comment|
          author = comment.author&.name || "Unknown"
          lines << "- **#{author}** (#{comment.author_type}): #{comment.body.truncate(200)}"
        end
      end

      lines << ""
      lines << "Use board MCP tools (`board_get_task`, `board_add_comment`, `board_move_task`) to interact with the board."
      lines.join("\n")
    end
  end
end
