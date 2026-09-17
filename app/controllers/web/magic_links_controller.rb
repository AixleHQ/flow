# frozen_string_literal: true

# Emailed single-use sign-in links (CAP-4).
class Web::MagicLinksController < Web::ApplicationController
  layout "inertia"

  skip_before_action :enforce_company_auth_policy
  skip_before_action :enforce_onboarding
  skip_before_action :redirect_super_admin_to_admin_panel

  # POST /login/magic
  def create
    # Stepping up: the address is already known, and asking a signed-in person to
    # retype it would be theatre. Anonymous callers still supply one.
    requested = params[:email].presence || (current_user&.email if signed_in?)
    user = User.active.not_deleted.find_by(email: requested.to_s.strip.downcase)

    # Always the same answer, whether or not that address exists: the response
    # must not become an account-existence oracle.
    if user && magic_link_offered_to?(user)
      record, token = MagicLinkToken.issue!(user, requested_ip: request.remote_ip)
      MagicLinkMailer.sign_in(user, token).deliver_later if record.persisted?
    end

    redirect_to login_path(sent: "1")
  end

  # GET /login/magic/:token — CONFIRM, do not consume.
  #
  # Mail scanners and link-preview bots fetch every URL in a message. If the GET
  # signed people in, the link would routinely be dead by the time its owner
  # clicked it — and worse, it would have been "used" by whoever scanned it. So
  # the GET only renders a button, and the POST below is what burns the token.
  def show
    render inertia: "Auth/MagicLinkPage", props: { token: params[:token] }
  end

  # POST /login/magic/:token
  def confirm
    provider = IdentityProvider.deployment!("magic_link")
    assertion = Auth::Registry.for(provider).complete(token: params[:token])
    return redirect_to(login_path(error: "magic_link_invalid")) if assertion.nil?

    user = Auth::IdentityResolver.new(assertion, auto_join: false).resolve
    return redirect_to(login_path(error: "account_deleted")) if user.deleted?
    return redirect_to(login_path(error: "pending_approval")) if no_active_membership?(user)

    sign_in_or_prove(user, provider: provider)
    redirect_to company_projects_path
  rescue Auth::IdentityResolver::SuperAdminProviderError
    redirect_to login_path(error: "super_admin_password_only")
  end

  private

  # A link is only worth sending when some company this person belongs to would
  # actually accept it — otherwise the mail promises a door that is bolted.
  def magic_link_offered_to?(user)
    return false unless Auth::PolicyResolver.deployment_allowlist_kinds.include?("magic_link")

    magic_link_id = IdentityProvider.deployment!("magic_link").id
    user.company_memberships.active.any? do |membership|
      Auth::PolicyResolver.allowed_provider_ids(membership.company).include?(magic_link_id)
    end
  end

  def no_active_membership?(user)
    !user.super_admin? && user.company_memberships.active.none?
  end
end
