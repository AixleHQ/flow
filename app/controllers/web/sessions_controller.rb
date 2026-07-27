# frozen_string_literal: true

class Web::SessionsController < Web::ApplicationController
  layout "inertia"

  skip_before_action :enforce_onboarding
  skip_before_action :redirect_super_admin_to_admin_panel, only: %i[omniauth failure]

  def new
    if signed_in?
      target = onboarding_done?(current_user) ? company_projects_path : onboarding_path
      redirect_to target
      return
    end

    render inertia: "Auth/LoginPage", props: {
      error: params[:error],
      # Pre-fill support for the invitation flow (/login?email=...). Echoed
      # back only when it actually looks like an email address.
      email: safe_email_param
    }
  end

  def create
    user_form = UserSignInForm.new(session_params)
    return redirect_to(login_path, inertia: { errors: user_form.errors }) unless user_form.valid?

    user = user_form.user
    # A parked invitation (login-continuation) is accepted before the gate below
    # so the invited membership is already active, and the inviting company is
    # already the current one.
    accept_pending_invitation(user)

    # Same gate as #omniauth, and it must run BEFORE sign_in: a user with no
    # active membership would otherwise be walked all the way through
    # onboarding (enforce_onboarding runs before require_active_membership!)
    # and only then signed out at the first company-scoped page.
    return redirect_to login_path(error: "pending_approval") if no_active_membership?(user)

    sign_in(user)
    target = onboarding_done?(user) ? company_projects_path : onboarding_path
    redirect_to target
  end

  def destroy
    sign_out
    redirect_to login_path
  end

  def omniauth
    auth_service = GoogleOmniAuthService.new(request.env["omniauth.auth"])
    user = auth_service.authenticate

    # An invitation being accepted always wins over the pending gate below:
    # accepting turns the invited membership active BEFORE we check for active
    # memberships. (Auto-join already skips users with any membership, so an
    # invited user is never domain-auto-joined either.)
    accept_pending_invitation(user)

    # Pending = platform-level pending account state OR no active membership
    # yet (fresh OAuth user with no domain match, or auto-joined into a company
    # that requires admin approval). Super admins have no memberships.
    # A soft-deleted account must not get a session: find_or_initialize_by finds
    # it by email, but AuthConcern#current_user filters it out, so signing it in
    # produces a redirect loop instead of a refusal.
    return redirect_to login_path(error: "account_deleted") if user.deleted?

    if user.pending? || no_active_membership?(user)
      redirect_to login_path(error: "pending_approval")
      return
    end

    sign_in(user)
    target = user.super_admin? ? admin_root_path : onboarding_path
    redirect_to target
  rescue StandardError
    redirect_to login_path(error: "oauth_failed")
  end

  def failure
    error_type = params[:message] || "oauth_failed"
    redirect_to login_path(error: error_type)
  end

  private

  # Onboarding lives on the membership the user will land in — the switcher's
  # remembered company, else the oldest. Resolved here rather than read off the
  # user, which no longer carries onboarding at all.
  def onboarding_done?(user)
    return true if user.super_admin?

    landing_membership(user)&.onboarding_completed? || false
  end

  def landing_membership(user)
    memberships = user.company_memberships.active.to_a
    memberships.find { |m| m.company_id == user.last_company_id } ||
      memberships.min_by { |m| [ m.accepted_at ? 1 : 0, m.accepted_at || Time.at(0), m.id ] }
  end

  # Super admins legitimately have none (they live in /admin). For everyone
  # else, no active membership means there is nothing to sign in to: a fresh
  # OAuth user whose domain matched nothing, a company that requires admin
  # approval (membership still `invited`), or a fully revoked member.
  # Deliberately a live query — the invitation just accepted above may have
  # flipped a membership active.
  def no_active_membership?(user)
    !user.super_admin? && user.company_memberships.active.none?
  end

  def session_params
    if params.key?(:user)
      params.require(:user).permit(:email, :password)
    else
      params.permit(:email, :password)
    end
  end

  def safe_email_param
    email = params[:email].to_s.strip
    email if email.match?(URI::MailTo::EMAIL_REGEXP)
  end
end
