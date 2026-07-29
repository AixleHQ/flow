# frozen_string_literal: true

class Web::Company::Projects::SettingsController < Web::Company::Projects::ApplicationController
  def show
    render inertia: "Projects/Settings/SettingsPage", props: {
      project: settings_project_props,
      members: project_members_props
    }
  end

  def update
    if current_project.update(project_params)
      redirect_to company_project_settings_path(current_project), notice: "Project updated successfully"
    else
      redirect_back fallback_location: company_project_settings_path(current_project),
                     inertia: { errors: current_project.errors }
    end
  end

  private

  def project_params
    params.require(:project).permit(:name, :description, :preferred_artifacts_language, :state)
  end

  def settings_project_props
    project = current_project
    {
      id: project.id,
      name: project.name,
      description: project.description,
      slug: project.slug,
      state: project.state,
      preferred_artifacts_language: project.preferred_artifacts_language,
      created_at: project.created_at.iso8601,
      updated_at: project.updated_at.iso8601,
      owner_name: project.owner.name,
      owner_email: project.owner.email,
      sessions_count: project.terminal_sessions.count,
      workflows_count: project.workflows.where(deleted_at: nil).count,
      board_tasks_count: project.board&.board_tasks&.count || 0,
      repositories_count: project.repositories.count,
      integrations_count: Integration.visible_for_project(project).count,
      can_delete: project.admin?(current_user) || current_project_membership&.admin? || false
    }
  end

  def project_members_props
    current_project.member_users.map do |user|
      {
        id: user.id,
        name: user.name,
        email: user.email,
        is_owner: user.id == current_project.owner_id
      }
    end
  end
end
