# frozen_string_literal: true

class Web::Company::Projects::SettingsController < Web::Company::Projects::ApplicationController
  def show
    render inertia: "Projects/Settings/SettingsPage", props: {
      project: settings_project_props
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
      can_delete: project.admin?(current_user) || current_project_membership&.admin? || false
    }
  end
end
