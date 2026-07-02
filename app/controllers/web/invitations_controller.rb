# frozen_string_literal: true

# Public invitation-acceptance flow (the link from MembershipMailer). Viewing
# needs no session — the signed token itself is the credential (email-ownership
# proof) — but a membership is only ever accepted into the User it was issued
# for, never attached to a mismatched signed-in account.
class Web::InvitationsController < Web::ApplicationController
  layout "inertia"

  skip_before_action :enforce_onboarding
  skip_before_action :redirect_super_admin_to_admin_panel

  # GET /invitations/:token — branches on token validity + who is signed in.
  def show
    return render_invitation("expired") unless membership

    invitee = membership.user

    if signed_in?
      if current_user.id == invitee.id
        render_invitation("accept", invited_email: invitee.email)
      else
        render_invitation("wrong_account",
                          invited_email: mask_email(invitee.email),
                          current_email: current_user.email)
      end
    elsif invitee.password_digest.present? || invitee.provider.present?
      # Existing credentials: continue via the regular login flow. The token is
      # parked in the session and auto-accepted right after sign-in (see
      # AuthConcern#accept_pending_invitation).
      session[:pending_invitation_token] = params[:token]
      render_invitation("login", invited_email: invitee.email)
    else
      # Park the token here too: a passwordless invitee may pick "Continue
      # with Google" instead of setting a password, and the OAuth callback
      # (sessions#omniauth) accepts the parked invitation right after auth.
      session[:pending_invitation_token] = params[:token]
      render_invitation("signup", invited_email: invitee.email, invitee_name: invitee.name)
    end
  end

  # POST /invitations/:token/accept — signed-in invitee only.
  def accept
    return redirect_to invitation_path(params[:token]) unless membership && invitee_signed_in?

    # Concurrent accept (double click / two tabs): degrade to the invitation
    # page (which shows the current token state) instead of raising.
    return redirect_to invitation_path(params[:token]) unless safely_accept(membership)

    session[:current_company_id] = membership.company_id
    session.delete(:pending_invitation_token)
    redirect_to company_projects_path, notice: "Welcome to #{membership.company.name}!"
  end

  # POST /invitations/:token/decline — signed-in invitee only; declining
  # revokes the membership (which also invalidates the token).
  def decline
    return redirect_to invitation_path(params[:token]) unless membership && invitee_signed_in?

    membership.revoke!
    session.delete(:pending_invitation_token)
    redirect_to root_path, notice: "Invitation declined"
  end

  # POST /invitations/:token/signup — first-time users only (invited User has
  # neither a password nor OAuth): set name+password, accept, sign in.
  def signup
    return redirect_to invitation_path(params[:token]) unless membership && signup_allowed?

    error = validate_signup_password
    return redirect_to invitation_path(params[:token]), inertia: { errors: error } if error

    invitee = membership.user
    invitee.name = signup_params[:name] if signup_params[:name].present?
    invitee.password = signup_params[:password]

    if invitee.save
      return redirect_to invitation_path(params[:token]) unless safely_accept(membership)

      sign_in(invitee)
      session[:current_company_id] = membership.company_id
      session.delete(:pending_invitation_token)
      target = invitee.onboarding_state == "completed" ? company_projects_path : onboarding_path
      redirect_to target, notice: "Welcome to #{membership.company.name}!"
    else
      redirect_to invitation_path(params[:token]), inertia: { errors: invitee.errors }
    end
  end

  private

  def membership
    @membership ||= CompanyMembership.find_by_token_for(:invitation, params[:token])
  end

  # Lock + re-check so a concurrent accept is a graceful no-op, not an
  # AASM::InvalidTransition 500.
  def safely_accept(membership)
    membership.with_lock { membership.may_accept? && membership.accept! }
  end

  def invitee_signed_in?
    signed_in? && current_user.id == membership.user_id
  end

  def signup_allowed?
    invitee = membership.user
    !signed_in? && invitee.password_digest.blank? && invitee.provider.blank?
  end

  def signup_params
    params.permit(:name, :password, :password_confirmation)
  end

  def validate_signup_password
    return { password: "Password is required" } if signup_params[:password].blank?
    return { password_confirmation: "Passwords do not match" } if signup_params[:password] != signup_params[:password_confirmation]

    nil
  end

  # Props use camelCase keys directly (Inertia props are not auto-transformed).
  def render_invitation(variant, extra = {})
    props = { variant: variant, token: params[:token] }

    if membership
      props[:company] = { name: membership.company.name }
      props[:role] = membership.role.to_s
      props[:inviterName] = membership.invited_by&.name
    end

    props[:invitedEmail] = extra[:invited_email] if extra.key?(:invited_email)
    props[:currentEmail] = extra[:current_email] if extra.key?(:current_email)
    props[:inviteeName] = extra[:invitee_name] if extra.key?(:invitee_name)

    render inertia: "Invitations/Show", props: props
  end

  # "jane.doe@example.com" -> "j***@example.com"
  def mask_email(email)
    local, domain = email.split("@", 2)
    "#{local.first}***@#{domain}"
  end
end
