# frozen_string_literal: true

class Web::Company::Projects::ApplicationController < Web::Company::ApplicationController
  inertia_share do
    {
      project: InertiaRails.always { project_props },
      projectPermissions: InertiaRails.always { project_permissions_props }
    }
  end

  private

  def current_project
    @current_project ||= Project.for_user(current_user)
                                .with_computed_counts
                                .find(params[:project_id])
  end

  def policy_context
    ProjectContext.new(current_user, params, project: current_project)
  end

  def project_props
    ProjectResource.new(current_project).to_h
  end

  # Membership in the PROJECT's company (not the session's current company) —
  # permissions must reflect the company the project belongs to.
  def current_project_membership
    return @current_project_membership if defined?(@current_project_membership)

    @current_project_membership = current_user.active_memberships.find { |m| m.company_id == current_project.company_id }
  end

  def project_permissions_props
    {
      canExecute: current_project_membership.present? && !current_project_membership.viewer?,
      canManage: (current_project_membership&.admin? || false) || current_project.admin?(current_user)
    }
  end
end
