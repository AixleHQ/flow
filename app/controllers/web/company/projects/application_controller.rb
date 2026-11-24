# frozen_string_literal: true

class Web::Company::Projects::ApplicationController < Web::Company::ApplicationController
  # A project's pages live under its own company's slug. One opened under
  # another (a project moved between companies, an edited link) goes to the same
  # page there before anything resolves the membership; a write is refused.
  prepend_before_action :follow_project_company

  rescue_from Versions::StaleVersion, Versions::InUse do |error|
    redirect_back fallback_location: company_project_path(current_project), alert: error.message
  end

  inertia_share do
    {
      project: InertiaRails.always { project_props },
      projectPermissions: InertiaRails.always { project_permissions_props }
    }
  end

  private

  def follow_project_company
    return unless signed_in?

    slug = current_project.company.slug
    return if slug == company_slug_in_path
    return render_not_found unless request.get? || request.head?

    flash.keep
    redirect_to request.fullpath.sub(%r{\A/company/[^/]+}, "/company/#{slug}")
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

  def ownership_props
    can_transfer = Web::Company::Projects::OwnershipsPolicy.new(policy_context, :ownerships).update?
    return { can_transfer: false, candidates: [] } unless can_transfer

    collaborator_ids = current_project.project_collaborators.pluck(:user_id).to_set
    candidates = ProjectHandover.candidate_rows(current_project.ownership_candidates)
                                .map { |c| c.merge(collaborator: collaborator_ids.include?(c[:id])) }

    { can_transfer: true, candidates: candidates }
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
