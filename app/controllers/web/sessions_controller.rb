# frozen_string_literal: true

class Web::SessionsController < Web::ApplicationController
  layout "inertia"

  skip_before_action :enforce_onboarding
  skip_before_action :redirect_super_admin_to_admin_panel, only: %i[omniauth failure]

  def new
    if signed_in?
      target = current_user.onboarding_state == "completed" ? company_projects_path : onboarding_path
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

    if user_form.valid?
      sign_in(user_form.user)
      # A parked invitation (login-continuation) is accepted before the
      # redirect so the inviting company is already the current one.
      accept_pending_invitation(user_form.user)
      target = user_form.user.onboarding_state == "completed" ? company_projects_path : onboarding_path
      redirect_to target
    else
      redirect_to login_path, inertia: { errors: user_form.errors }
    end
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
    if user.pending? || (!user.super_admin? && user.company_memberships.active.none?)
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
