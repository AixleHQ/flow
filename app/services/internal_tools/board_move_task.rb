# frozen_string_literal: true

module InternalTools
  class BoardMoveTask < Base
    tool do
      display_name "Board Move Task"
      description "Move a task to another board column by name."
      tags :board
      inject_when :workflow_step_session
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

      from_column_name = task.board_column.name
      actor = resolve_actor(task)
      TaskService.move(
        task: task,
        to_column: target_column,
        actor: actor,
        actor_type: :agent
      )

      success({
        id: task.id,
        number: task.number,
        title: task.title,
        from_column: from_column_name,
        to_column: target_column.name
      }.to_json)
    end

    private

    def resolve_actor(task)
      task.assignee || workflow_run&.user
    end
  end
end
