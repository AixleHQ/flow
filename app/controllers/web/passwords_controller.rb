# frozen_string_literal: true

# Setting or changing the signed-in person's own password, from Profile →
# Security. Like the rest of that page it sits behind the company entry gate
# (AD-5), so setting a first password needs no other proof than the session.
class Web::PasswordsController < Web::ApplicationController
  before_action :require_signed_in
  before_action :refuse_impersonation
  before_action :require_password_accepted

  # A stolen session must not become a free oracle for the current password.
  # Inert in test, where the cache is a null store.
  rate_limit to: 10, within: 10.minutes, only: :update, by: -> { current_user.id },
             with: -> { redirect_to security_profile_path, alert: "Too many attempts. Try again in a few minutes." }

  NOTICES = {
    "set" => "Password set. You can sign in with your email and password from now on.",
    "changed" => "Password changed. Your other devices were signed out."
  }.freeze

  # PATCH /profile/password
  def update
    form = PasswordForm.new(user: current_user, **password_params)
    if form.save(request: request)
      redirect_to security_profile_path, notice: NOTICES.fetch(form.event)
    else
      redirect_to security_profile_path, inertia: { errors: form.error_messages }
    end
  end

  private

  def password_params
    params.permit(:current_password, :password, :password_confirmation).to_h.symbolize_keys
  end

  def require_signed_in
    redirect_to login_path unless signed_in?
  end

  # A password set during an impersonation would let the operator sign in as
  # that person later without impersonating, outside its audit trail.
  def refuse_impersonation
    return unless impersonated?

    redirect_to security_profile_path, alert: "Passwords cannot be changed while impersonating."
  end

  def require_password_accepted
    return if Auth::SignInMethods.password_accepted?(current_user)

    redirect_to security_profile_path, alert: "None of your workspaces accepts a password."
  end
end
