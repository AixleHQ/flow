# frozen_string_literal: true

module PersonalTools
  class ListBoardTasks < Base
    tool do
      display_name "List Board Tasks"
      description "List tasks on a project's board one page at a time, optionally filtered by " \
                  "column, tag or archive state. Rows carry no description — read one with " \
                  "get_board_task."
      audience :user
      tags :board
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :column_id, type: :integer, description: "Filter to a board column id."
      param :tag, type: :string, description: "Filter by tag."
      param :archived, type: :boolean,
            description: "Filter by archive state: false returns only active tasks, " \
                         "true only archived ones. Omit to return both."
      param :limit, type: :integer, description: "Rows per page (default 50, cap 100)."
      param :offset, type: :integer,
            description: "Rows to skip before the page starts (default 0). The response " \
                         "carries `total` and `has_more`."
    end

    DEFAULT_LIMIT = 50
    MAX_LIMIT = 100

    def execute
      project = find_project!
      authorize!(project.board, :index?, policy: Web::Company::Projects::Board::TasksPolicy, project: project)
      board = project.board
      return error("This project has no board — create one with setup_board") unless board

      tasks = board.board_tasks.preload(:board_column, :assignee)
      tasks = tasks.where(board_column_id: params[:column_id]) if params[:column_id].present?
      tasks = tasks.with_tag(params[:tag]) if params[:tag].present?
      tasks = filter_by_archived(tasks)

      total = tasks.count
      limit = requested_limit
      offset = requested_offset
      rows = tasks.in_flat_board_order.limit(limit).offset(offset).map do |t|
        { id: t.id, title: t.title, task_type: t.task_type, priority: t.priority,
          column: t.board_column&.name, column_id: t.board_column_id,
          assignee: t.assignee&.name, assignee_id: t.assignee_id, tags: t.tags }
      end
      success(project_id: project.id, total: total, limit: limit, offset: offset,
              has_more: offset + rows.size < total, tasks: rows)
    end

    private

    def requested_limit
      params[:limit].present? ? params[:limit].to_i.clamp(1, MAX_LIMIT) : DEFAULT_LIMIT
    end

    def requested_offset
      [ params[:offset].to_i, 0 ].max
    end

    # Omitting the param lists both states, which is what callers written
    # before this filter existed already get. Only an explicit value narrows
    # the list — `false` to the active tasks, `true` to the archived ones.
    def filter_by_archived(scope)
      return scope if params[:archived].nil?

      ActiveModel::Type::Boolean.new.cast(params[:archived]) ? scope.archived : scope.active
    end
  end
end
