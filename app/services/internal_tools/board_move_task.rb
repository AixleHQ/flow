# frozen_string_literal: true

module InternalTools
  class BoardMoveTask < Base
    def execute
      require_workflow_context!
      board = BoardContextResolver.resolve(session)
      return error("No board available in current context") unless board

      task = board.board_tasks.find_by(id: params[:task_id])
      return error("Task not found on this board") unless task

      target_column = board.board_columns.find_by(name: params[:column_name])
      return error("Column '#{params[:column_name]}' not found") unless target_column

      actor = resolve_actor(task)
      TaskService.move(
        task: task,
        to_column: target_column,
        actor: actor,
        actor_type: :agent
      )

      success({
        id: task.id,
        title: task.title,
        from_column: task.board_column.name,
        to_column: target_column.name
      }.to_json)
    end

    private

    def resolve_actor(task)
      task.assignee || workflow_run&.user
    end
  end
end
