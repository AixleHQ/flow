# frozen_string_literal: true

module ContextBuilders
  class BoardContext < Base
    # Past this a description is a spec, and a cut-down spec reads as the whole one,
    # so the agent gets a pointer to board_get_task instead of a truncated copy.
    DESCRIPTION_INLINE_LIMIT = 1500

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
      lines << "- **Task:** ##{task.number} #{task.title} (id: #{task.id})"
      lines << "- **Column:** #{column.name}" if column
      lines << "- **Priority:** #{task.priority}" if task.priority.present?
      lines << "- **Description:** #{task.description}" if inline_description?(task)
      lines << "- **Tags:** #{task.tags.join(', ')}" if task.tags.present?
      lines << "- **Assignee:** #{task.assignee.name} (id: #{task.assignee_id})" if task.assignee
      lines << ""
      lines << fetch_hint(task)
      lines << ""
      lines.concat(continuity_lines(task))

      lines << ""
      lines << "### Board Columns"
      columns.each do |col|
        marker = col.id == column&.id ? " ← current" : ""
        lines << "- #{col.position}. **#{col.name}**#{marker}"
      end

      lines.join("\n")
    end

    def inline_description?(task)
      task.description.present? && task.description.length <= DESCRIPTION_INLINE_LIMIT
    end

    def continuity_lines(task)
      lines = [
        "### Decisions and related tasks",
        "Before changing code, read this task's comments with `board_get_comments(task_id: #{task.id})`."
      ]
      parent = task.board.board_tasks.find_by(id: task.parent_task_id, task_type: :epic) if task.parent_task_id.present?
      if parent
        lines << "Parent epic: ##{parent.number} #{parent.title} (id: #{parent.id}). " \
          "Read its full requirements and decisions with `board_get_task(task_id: #{parent.id})` " \
          "and `board_get_comments(task_id: #{parent.id})` before implementing."
      end

      epic_id = parent&.id || (task.id if task.task_type.epic?)
      if epic_id
        lines << "Find related subtasks with `board_list_tasks(parent_task_id: #{epic_id})` " \
          "(paginated: follow `has_more` and `offset`). Read referenced or relevant tasks " \
          "and their comments with `board_get_task` and `board_get_comments`."
      end
      lines << "Reconcile agreed decisions with the task and epic requirements; report unresolved " \
        "conflicts instead of silently overriding them. Task relationships do not imply execution " \
        "order or shared code: verify prerequisite PRs or commits on the working branch."
      lines
    end

    def fetch_hint(task)
      if task.description.present? && !inline_description?(task)
        "The task's description and comments are not repeated here: read them with " \
          "`board_get_task` and `board_get_comments`."
      else
        "The task's comments are not repeated here: read them with `board_get_comments`."
      end
    end
  end
end
