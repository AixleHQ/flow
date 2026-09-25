# frozen_string_literal: true

class Web::Company::ApplicationController < Web::ApplicationController
  include Pundit::Authorization
  include AuthorizationConcern

  layout "inertia"

  before_action :require_auth
  before_action :require_active_membership!
  before_action :dynamic_authorize!
  before_action :deny_read_only_mutation!

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  inertia_share do
    {
      permissions: InertiaRails.always {
        {
          is_admin: current_membership&.admin? || false,
          can_manage_members: current_membership&.admin? || false,
          can_manage_projects: current_membership&.admin? || false,
          can_write: current_membership.present? && !current_membership.viewer?
        }
      }
    }
  end

  # For a write that is the actor's own business — a favourite, which company
  # they are on, leaving one — rather than a change to what the company owns.
  def self.allow_viewer_writes(**options)
    skip_before_action :deny_read_only_mutation!, **options
  end

  private

  def policy_context
    BaseContext.new(current_user, params, company: current_company)
  end

  # The backstop behind the policies, as Api::V1 has: a viewer changes nothing
  # the company owns, whatever an action's policy says. Two policies once said
  # otherwise (a viewer could create a project, and review company artifacts).
  def deny_read_only_mutation!
    return if request.get? || request.head?
    return unless signed_in?

    membership = policy_context.membership
    user_not_authorized if membership.nil? || membership.viewer?
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

  # All sessions belonging to the current company, project-less ones (auth_setup)
  # included: every session records the company it acts for. Matching project-less
  # rows by owner instead showed a multi-company member's logins to all of their
  # companies.
  def company_sessions_scope
    TerminalSession.where(company_id: current_company.id)
  end
end
