# frozen_string_literal: true

module PersonalTools
  class ListMyTasks < Base
    tool do
      display_name "List My Tasks"
      description "List the board tasks assigned to you — directly or through a project team you are on — " \
                  "across every project you can reach in one company, or in one project. Tasks come " \
                  "grouped by project, each with the `number` people see on the board and no description " \
                  "or comments — read one with get_board_task. Archived tasks are left out."
      audience :user
      tags :board
      read_only
      param :project_id, type: :integer, description: "Only this project. Omit it to list every project in the company."
      param :company_id, type: :integer,
            description: "The company to list when project_id is omitted. Needed only when you belong to " \
                         "more than one (see list_companies)."
      param :limit, type: :integer, description: "Tasks per page (default 50, cap 100)."
      param :offset, type: :integer,
            description: "Tasks to skip before the page starts (default 0). The response carries `total` and `has_more`."
    end

    DEFAULT_LIMIT = 50
    MAX_LIMIT = 100

    def execute
      tasks = assigned_to_user.active.joins(board: :project).where(projects: { id: projects_in_scope })
      total = tasks.count
      offset = [ params[:offset].to_i, 0 ].max
      page = tasks.preload(:board_column, :assignee_team, board: :project)
                  .order("projects.name", "projects.id").in_flat_board_order
                  .limit(requested_limit).offset(offset).to_a

      success(total: total, has_more: offset + page.size < total, projects: grouped(page))
    end

    private

    def assigned_to_user
      BoardTask.where(assignee_id: user.id)
               .or(BoardTask.where(assignee_team_id: user.project_team_memberships.select(:project_team_id)))
    end

    def projects_in_scope
      return accessible_projects.where(company_id: resolve_company!.id) if params[:project_id].blank?

      project = find_project!
      authorize!(project.board, :index?, policy: Web::Company::Projects::Board::TasksPolicy, project: project)
      accessible_projects.where(id: project.id)
    end

    def grouped(tasks)
      tasks.group_by { |task| task.board.project }.map do |project, rows|
        { project_id: project.id, project_name: project.name, tasks: rows.map { |task| row(task) } }
      end
    end

    def row(task)
      { number: task.number, title: task.title, task_type: task.task_type, priority: task.priority,
        column: task.board_column&.name, tags: task.tags, team: task.assignee_team&.name }.compact
    end

    def requested_limit
      params[:limit].present? ? params[:limit].to_i.clamp(1, MAX_LIMIT) : DEFAULT_LIMIT
    end
  end
end
