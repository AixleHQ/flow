# frozen_string_literal: true

module InternalTools
  class BoardListTasks < Base
    tool do
      display_name "Board List Tasks"
      description "List tasks on the current board one page at a time, with optional filters for " \
                  "column, tag, task type, or assignee. Rows carry no description — read a task's " \
                  "description with board_get_task."
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
          },
          limit: {
            type: "integer",
            description: "Tasks per page (default 25, max 100)"
          },
          offset: {
            type: "integer",
            description: "Tasks to skip before the page starts (default 0). The response carries " \
                         "`total` and `has_more`; prefer a filter over walking a large board"
          }
        }
      })
    end

    # A row still carries gates, recent runs and counts, so a page is far from free
    # even with descriptions gone. 25 is what the board page itself loads per column.
    DEFAULT_LIMIT = 25
    MAX_LIMIT = 100

    # The three counts a card shows, as scalar subqueries in the page's own query —
    # the alternative is three extra queries per task.
    COUNTS_SQL = <<~SQL.squish
      board_tasks.*,
      (SELECT COUNT(*) FROM task_comments WHERE board_task_id = board_tasks.id) AS comments_count,
      (SELECT COUNT(*) FROM board_tasks children WHERE children.parent_task_id = board_tasks.id) AS children_count,
      (SELECT COUNT(*) FROM task_assets WHERE board_task_id = board_tasks.id) AS assets_count
    SQL

    def execute
      require_workflow_context!
      board = BoardContextResolver.resolve(session)
      return error("No board available in current context") unless board

      scope = filtered(board.board_tasks)
      total = scope.count
      limit = requested_limit
      offset = requested_offset
      rows = page(scope, limit, offset).map { |task| row(task) }

      success({ tasks: rows, total: total, limit: limit, offset: offset,
                has_more: offset + rows.size < total }.to_json)
    end

    private

    def filtered(scope)
      scope = scope.joins(:board_column).where(board_columns: { name: params[:column_name] }) if params[:column_name].present?
      scope = scope.with_tag(params[:tag]) if params[:tag].present?
      scope = scope.where(task_type: params[:task_type]) if params[:task_type].present?
      scope = scope.where(assignee_id: params[:assignee_id]) if params[:assignee_id].present?
      scope
    end

    # `preload` rather than `includes`: the flat ordering already joins
    # board_columns, and a second strategy on the same query would fight the
    # custom SELECT above. board_column itself is not preloaded — a row reports
    # `board_column_id`, never the column record.
    def page(scope, limit, offset)
      scope.select(Arel.sql(COUNTS_SQL))
           .preload(:assignee, :workflow_runs, :gates)
           .in_flat_board_order
           .limit(limit)
           .offset(offset)
    end

    # Descriptions are the one unbounded field on a task, and listing a whole
    # board's worth of them is what used to make this tool cost thousands of
    # tokens. Dropped after serialization rather than left out of the SELECT
    # because the resource reads the attribute.
    def row(task)
      BoardTaskResource.new(task, params: { snake_keys: true }).to_h.except("description")
    end

    def requested_limit
      params[:limit].present? ? params[:limit].to_i.clamp(1, MAX_LIMIT) : DEFAULT_LIMIT
    end

    def requested_offset
      [ params[:offset].to_i, 0 ].max
    end
  end
end
