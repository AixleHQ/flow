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
      columns = board.board_columns.order(:position)

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
      lines << "- **Assignee:** #{task.assignee.name} (id: #{task.assignee_id})" if task.assignee

      lines << ""
      lines << "### Board Columns"
      columns.each do |col|
        marker = col.id == column&.id ? " ← current" : ""
        lines << "- #{col.position}. **#{col.name}**#{marker}"
      end

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
      lines << "### Board Tools"
      lines << ""
      lines << "- **board_get_board_info** — get board details with all columns"
      lines << "- **board_list_tasks** — list tasks on the board (filter by column_name, status)"
      lines << "- **board_get_task** — get full task details by task_id"
      lines << "- **board_get_comments** — get comments for a task"
      lines << "- **board_get_task_assets** — get assets attached to a task"
      lines << "- **board_add_comment** — add a comment to a task (markdown supported in body)"
      lines << "- **board_update_task** — update task fields (title, description, priority, assignee_id, etc)"
      lines << "- **board_create_task** — create a new task on the board (optionally assignee_id)"
      lines << "- **board_move_task** — move a task to a different column by column_name"
      lines << "- **board_attach_asset** — attach a file to a task (use file_path for screenshots, file_content for small text)"
      lines << "- **board_manage_tags** — add/remove tags on a task"
      lines << "- **board_list_members** — list project members with the user ids to assign a task to"

      lines.join("\n")
    end
  end
end
