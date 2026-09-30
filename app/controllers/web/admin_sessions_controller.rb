# frozen_string_literal: true

class Web::AdminSessionsController < Web::ApplicationController
  layout "inertia"

  skip_before_action :enforce_onboarding
  skip_before_action :enforce_workspace
  skip_before_action :enforce_company_auth_policy

  def new
    render inertia: "Auth/AdminLoginPage"
  end

  def create
    form = UserSignInForm.new(params.permit(:email, :password))
    user = form.user if form.valid?

    # Anyone else gets the same answer as a wrong password, so this screen
    # cannot tell which addresses belong to an operator.
    unless user&.super_admin?
      if form.errors.empty?
        form.errors.add(:email, :email_or_password_incorrect)
        form.errors.add(:password, :email_or_password_incorrect)
      end
      return redirect_to(admin_login_path, inertia: { errors: form.errors })
    end

    sign_in(user, provider: Auth::LocalCredential.link!(user))
    # /admin is Administrate, not an Inertia page: a plain redirect would land
    # its HTML in Inertia's error modal.
    request.headers["X-Inertia"].present? ? inertia_location(admin_root_path) : redirect_to(admin_root_path)
  end
end
