# frozen_string_literal: true

class Web::Company::Projects::ApplicationController < Web::Company::ApplicationController
  # A project opened from another of the user's companies (a deep link, a
  # notification) moves the session to that company before anything resolves
  # the membership, so the page, its sidebar and the next navigation all agree.
  prepend_before_action :follow_project_company

  inertia_share do
    {
      project: InertiaRails.always { project_props },
      projectPermissions: InertiaRails.always { project_permissions_props }
    }
  end

  private

  # Everything a project page shows or writes — config items, the member list,
  # integrations, analytics — belongs to the project's company, whichever
  # company the session was on when the page was requested.
  def current_company
    membership = current_user.active_memberships_with_company.find { |m| m.company_id == current_project.company_id }
    membership&.company || current_project.company
  end

  def follow_project_company
    return unless signed_in?

    company_id = current_project.company_id
    session[:current_company_id] = company_id if session[:current_company_id].to_i != company_id
  rescue ActiveRecord::RecordNotFound
    # Refused later, by the same lookup and the same gates as before this ran.
    nil
  end

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
      canManage: (current_project_membership&.admin? || false) || current_project.admin?(current_user),
      # Company-wide resources shown on a project page (a Slack install) are the
      # company admin's to change, not the project's.
      canManageCompany: current_project_membership&.admin? || false
    }
  end
end
