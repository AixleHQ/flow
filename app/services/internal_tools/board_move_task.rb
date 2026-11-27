# frozen_string_literal: true

module InternalTools
  class BoardMoveTask < Base
    tool do
      display_name "Board Move Task"
      description "Move a task to another board column by name, optionally to a position within it " \
                  "(0 = top). Without a position the task goes to the bottom of the column."
      tags :board
      input_schema({
        type: "object",
        required: %w[column_name],
        properties: {
          task_id: {
            type: "integer",
            description: TASK_ID_PARAM
          },
          task_number: {
            type: "integer",
            description: TASK_NUMBER_PARAM
          },
          column_name: {
            type: "string",
            description: "Destination column name"
          },
          position: {
            type: "integer",
            minimum: 0,
            description: "Optional 0-based position within the destination column (0 = top). " \
                         "Omit it to put the task at the bottom."
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

      target_column = board.board_columns.find_by(name: params[:column_name])
      return error("Column '#{params[:column_name]}' not found") unless target_column

      position = params[:position]
      return error("position must be a non-negative integer") unless position.nil? || (position.is_a?(Integer) && position >= 0)

      actor = session_user
      return error("Cannot determine the acting user") unless actor

      from_column_name = task.board_column.name
      draft_test = draft_test_run?
      TaskService.move(
        task: task,
        to_column: target_column,
        position: position,
        actor: actor,
        actor_type: :agent,
        start_column_workflow: !draft_test
      )

      result = {
        id: task.id,
        number: task.number,
        title: task.title,
        from_column: from_column_name,
        to_column: target_column.name,
        position: task.position
      }
      if draft_test && target_column.column_workflow_binding&.trigger_mode&.to_sym == :auto
        result[:column_workflow] = "not started: this is a test run of a workflow draft"
      end
      success(result.to_json)
    end
  end
end
