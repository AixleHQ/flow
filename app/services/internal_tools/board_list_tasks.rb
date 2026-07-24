# frozen_string_literal: true

module InternalTools
  class BoardListTasks < Base
    tool do
      display_name "Board List Tasks"
      description "List tasks on the current board with optional filters for column, tag, task type, or assignee."
      tags :board
      inject_when :workflow_step_session
      input_schema({
        type: "object",
        required: [],
        properties: {
          tag: {
            type: "string",
            description: "Filter tasks by tag"
          },
          task_type: {
            type: "string",
            description: "Filter tasks by task type"
          },
          assignee_id: {
            type: "integer",
            description: "Filter tasks by assignee user ID"
          },
          column_name: {
            type: "string",
            description: "Filter tasks to a board column by name"
          }
        }
      })
    end

    def execute
      require_workflow_context!
      board = BoardContextResolver.resolve(session)
      return error("No board available in current context") unless board

      tasks = board.board_tasks
                   .select(Arel.sql(<<~SQL.squish))
                     board_tasks.*,
                     (SELECT COUNT(*) FROM task_comments WHERE board_task_id = board_tasks.id) AS comments_count,
                     (SELECT COUNT(*) FROM board_tasks children WHERE children.parent_task_id = board_tasks.id) AS children_count,
                     (SELECT COUNT(*) FROM task_assets WHERE board_task_id = board_tasks.id) AS assets_count
                   SQL
                   .includes(:board_column, :assignee, :workflow_runs, :pending_gates)
      tasks = tasks.joins(:board_column).where(board_columns: { name: params[:column_name] }) if params[:column_name].present?
      tasks = tasks.with_tag(params[:tag]) if params[:tag].present?
      tasks = tasks.where(task_type: params[:task_type]) if params[:task_type].present?
      tasks = tasks.where(assignee_id: params[:assignee_id]) if params[:assignee_id].present?

      result = tasks.map { |t| BoardTaskResource.new(t).to_h }
      success(result.to_json)
    end
  end
end
