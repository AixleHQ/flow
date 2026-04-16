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
      error: params[:error]
    }
  end

  def create
    user_form = UserSignInForm.new(session_params)

    if user_form.valid?
      sign_in(user_form.user)
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

    if user.pending?
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
end
