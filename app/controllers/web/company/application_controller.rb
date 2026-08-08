# frozen_string_literal: true

class Web::Company::ApplicationController < Web::ApplicationController
  include Pundit::Authorization
  include AuthorizationConcern

  layout "inertia"

  before_action :require_auth
  before_action :require_active_membership!
  before_action :dynamic_authorize!

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  inertia_share do
    {
      permissions: InertiaRails.always {
        {
          is_admin: current_membership&.admin? || false,
          can_manage_members: current_membership&.admin? || false,
          can_manage_projects: current_membership&.admin? || false
        }
      }
    }
  end

  private

  def policy_context
    BaseContext.new(current_user, params, company: current_company)
  end

  def user_not_authorized
    redirect_back fallback_location: root_path, alert: "You are not authorized to perform this action."
  end

  def require_auth
    redirect_to login_path unless signed_in?
  end

  # Company-scoped screens need an active membership. A user whose memberships
  # were all revoked (or who never had one) is signed out. Distinct error key
  # from the OAuth "pending_approval" flow — this user LOST access, they are
  # not waiting for it.
  def require_active_membership!
    return if !signed_in? || current_membership.present?

    sign_out
    redirect_to login_path(error: "no_active_membership")
  end

  def require_admin
    head :forbidden unless current_membership&.admin?
  end

  # Second gate on top of the company/project scoping every session screen
  # already applies: reaching a session record is not the same as being allowed
  # to watch someone work. TerminalSession#visible_to? reads the OWNER's profile
  # preferences, and no role overrides them (see the model). Raising Pundit's
  # error keeps the refusal identical to a policy denial — the same redirect,
  # the same flash — instead of inventing a second "not authorized" shape.
  def authorize_session_visibility!(session)
    raise Pundit::NotAuthorizedError unless session.visible_to?(current_user)

    session
  end

  # All sessions belonging to the current company: sessions in the company's
  # projects, plus project-less sessions (e.g. auth_setup) of active members.
  # The user_id branch is restricted to project-less rows so a dual-membership
  # user's sessions in another company's projects never leak in.
  def company_sessions_scope
    member_ids = User.for_company(current_company).merge(CompanyMembership.active).select(:id)

    TerminalSession.left_joins(:project)
                   .where("projects.company_id = ? OR (terminal_sessions.project_id IS NULL AND terminal_sessions.user_id IN (?))",
                          current_company.id, member_ids)
  end
end
