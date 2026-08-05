# frozen_string_literal: true

class Web::Company::ProjectsController < Web::Company::ApplicationController
  def index
    # Current-company slice only: a dual-membership user must not see their
    # other companies' projects here (for_user alone spans all memberships).
    projects = Project.for_user(current_user)
                      .for_company(current_company)
                      .includes(:owner, :collaborators)
                      .select(
                        "projects.*",
                        "(SELECT COUNT(*) FROM project_collaborators WHERE project_collaborators.project_id = projects.id) AS cached_collaborators_count",
                        "(SELECT MAX(terminal_sessions.started_at) FROM terminal_sessions WHERE terminal_sessions.project_id = projects.id) AS cached_last_activity_at",
                        "(SELECT COUNT(*) FROM terminal_sessions WHERE terminal_sessions.project_id = projects.id) AS cached_sessions_count",
                        "(SELECT COUNT(*) FROM workflows WHERE workflows.scope_type = 'Project' AND workflows.scope_id = projects.id AND workflows.deleted_at IS NULL) AS cached_workflows_count",
                        "(SELECT COUNT(*) FROM board_tasks INNER JOIN boards ON boards.id = board_tasks.board_id WHERE boards.project_id = projects.id) AS cached_board_tasks_count"
                      )
                      .order(:name)

    render inertia: "Projects/IndexPage", props: {
      projects: projects.map { |p| ProjectResource.new(p, params: { with_members: true }).to_h }
    }
  end

  def show
    redirect_to company_project_overview_index_path(params[:id])
  end

  def create
    project = current_company.projects.new(project_params.merge(owner: current_user))

    if project.save
      redirect_to company_project_overview_index_path(project)
    else
      redirect_to company_projects_path, inertia: { errors: project.errors }
    end
  end

  def destroy
    project = Project.for_user(current_user).find(params[:id])
    project.destroy!
    redirect_to company_projects_path, notice: "Project deleted"
  end

  private

  def project_params
    params.require(:project).permit(:name, :description)
  end
end
