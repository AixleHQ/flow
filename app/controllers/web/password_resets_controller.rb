# frozen_string_literal: true

# Forgotten passwords. The address is asked for on a page of its own; the
# emailed link opens a form, and only submitting that form spends the link.
# Mail scanners fetch every URL in a message, so the GET changes nothing.
class Web::PasswordResetsController < Web::ApplicationController
  layout "inertia"

  skip_before_action :enforce_company_auth_policy
  skip_before_action :enforce_onboarding

  # Anyone may make us mail an address of their choosing here. Inert in test,
  # where the cache is a null store.
  rate_limit to: 10, within: 1.hour, only: :create, by: -> { request.remote_ip },
             with: -> { redirect_to new_password_reset_path, alert: "Too many attempts. Try again in an hour." }

  # GET /password/reset
  def new
    render inertia: "Auth/PasswordResetRequestPage", props: {
      email: safe_email_param,
      sent: params[:sent].present?
    }
  end

  # POST /password/reset
  def create
    # "Forgot your current password?" on Profile → Security: the address is
    # already known, and only that one is ever sent a link from a session.
    requested = signed_in? ? current_user.email : params[:email].to_s.strip
    user = User.authenticatable.find_by(email: requested)

    # Always the same answer, whether or not that address has an account: the
    # response must not become an account-existence oracle.
    PasswordMailer.reset(user).deliver_later if user && Auth::SignInMethods.password_accepted?(user)

    if signed_in?
      redirect_to security_profile_path, notice: "We sent a link to #{current_user.email}. It works once and expires in an hour."
    else
      redirect_to new_password_reset_path(sent: "1")
    end
  end

  # GET /password/reset/:token
  def edit
    render inertia: "Auth/PasswordResetPage", props: {
      token: params[:token],
      valid: reset_user.present?,
      min_length: User::PASSWORD_MIN_LENGTH
    }
  end

  # PATCH /password/reset/:token
  def update
    user = reset_user
    return redirect_to(edit_password_reset_path(token: params[:token])) if user.nil?

    # Asked before the password changes: a reset made from a browser already
    # signed in as this person keeps that browser signed in.
    own_browser = signed_in? && current_user == user
    form = PasswordForm.new(user: user, reset_token: params[:token], **password_params)
    unless form.save(request: request)
      return redirect_to edit_password_reset_path(token: params[:token]), inertia: { errors: form.error_messages }
    end

    if own_browser
      redirect_to security_profile_path, notice: "Password reset. Your other devices were signed out."
    else
      redirect_to login_path(email: user.email), notice: "Password reset. Sign in with your new password."
    end
  end

  private

  def reset_user
    return @reset_user if defined?(@reset_user)

    user = User.authenticatable.find_by_password_reset_token(params[:token].to_s)
    @reset_user = user if user && Auth::SignInMethods.password_accepted?(user)
  end

  def password_params
    params.permit(:password, :password_confirmation).to_h.symbolize_keys
  end

  def safe_email_param
    email = params[:email].to_s.strip
    email if email.match?(URI::MailTo::EMAIL_REGEXP)
  end
end
