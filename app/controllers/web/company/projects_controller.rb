# frozen_string_literal: true

class Web::Company::ProjectsController < Web::Company::ApplicationController
  def index
    projects = Project.for_user(current_user)
                      .includes(:project_collaborators)
                      .select(
                        "projects.*",
                        "(SELECT MAX(terminal_sessions.started_at) FROM terminal_sessions WHERE terminal_sessions.project_id = projects.id) AS cached_last_activity_at",
                        "(SELECT COUNT(*) FROM terminal_sessions WHERE terminal_sessions.project_id = projects.id) AS cached_sessions_count",
                        "(SELECT COUNT(*) FROM workflows WHERE workflows.scope_type = 'Project' AND workflows.scope_id = projects.id AND workflows.deleted_at IS NULL AND workflows.kind = 'standard') AS cached_workflows_count",
                        "(SELECT COUNT(*) FROM board_tasks INNER JOIN boards ON boards.id = board_tasks.board_id WHERE boards.project_id = projects.id) AS cached_board_tasks_count"
                      )
                      .order(:name)

    templates = WorkflowTemplate.visible_to(current_user, current_company)
                                .includes(:owner, :current_version)
                                .where.not(current_version_id: nil)
                                .order(:name)

    render inertia: "Projects/IndexPage", props: {
      projects: projects.map { |p| ProjectResource.new(p).to_h },
      workflow_templates: -> { templates.map { |t| WorkflowTemplateResource.new(t).to_h } }
    }
  end

  def show
    redirect_to company_project_overview_index_path(params[:id])
  end

  def create
    project = current_company.projects.new(project_params.merge(owner: current_user))

    if project.save
      instantiate_template!(project) if params.dig(:project, :workflow_template_version_id).present?
      redirect_to company_project_overview_index_path(project)
    else
      redirect_to company_projects_path, inertia: { errors: project.errors }
    end
  rescue WorkflowTemplateInstantiator::Error => e
    project&.destroy
    redirect_to company_projects_path, alert: e.message
  end

  def destroy
    project = Project.for_user(current_user).find(params[:id])
    project.destroy!
    redirect_to company_projects_path, notice: "Project deleted"
  end

  private

  def project_params
    params.require(:project).permit(:name, :description, :workflow_template_version_id)
  end

  def instantiate_template!(project)
    version = WorkflowTemplateVersion
              .joins(:workflow_template)
              .merge(WorkflowTemplate.visible_to(current_user, current_company))
              .find(params.dig(:project, :workflow_template_version_id))

    WorkflowTemplateInstantiator.new(project: project, version: version, user: current_user)
                              .instantiate!(set_project_origin: true)
  end
end
