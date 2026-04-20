# frozen_string_literal: true

class Web::Company::Projects::ApplicationController < Web::Company::ApplicationController
  inertia_share do
    { project: InertiaRails.always { project_props } }
  end

  private

  def current_project
    @current_project ||= Project.for_user(current_user)
                                .with_computed_counts
                                .includes(:project_collaborators)
                                .find(params[:project_id])
  end

  def policy_context
    ProjectContext.new(current_user, params, project: current_project)
  end

  def project_props
    ProjectResource.new(current_project).to_h
  end
end
