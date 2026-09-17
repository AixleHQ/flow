# frozen_string_literal: true

# Sign-in through a company's own OpenID Connect provider (CAP-3).
#
# Not an OmniAuth strategy: a customer's issuer and client credentials are a
# database row, and OmniAuth registers strategies at boot (AD-4). The redirect
# state, the PKCE verifier and the OIDC nonce are held server-side by
# Auth::State — never in the URL.
class Web::OidcSessionsController < Web::ApplicationController
  layout "inertia"

  skip_before_action :verify_authenticity_token, only: :callback
  skip_before_action :enforce_company_auth_policy
  skip_before_action :enforce_onboarding
  skip_before_action :redirect_super_admin_to_admin_panel

  # POST /login/sso — enterprise SSO discovery from the login screen. The user
  # types the address they would sign in with; the company is resolved from its
  # domain (already unique per company), and its single enabled connection starts
  # immediately. This is the only way in for a member of an SSO-only company who
  # is not signed in yet and therefore never reaches the step-up screen.
  def discover
    company = Company.find_by_email_domain(params[:email].to_s)
    connections = company ? startable_connections(company) : []

    case connections.size
    when 0 then redirect_to login_path(error: "no_sso_connection", email: params[:email])
    when 1 then redirect_to oidc_start_path(id: connections.first.id), status: :see_other
    else
      # More than one: let them choose rather than guessing on their behalf.
      render inertia: "Auth/SsoChoicePage", props: {
        company_name: company.branded_name,
        connections: connections.map { |c| { id: c.id, name: c.display_name } }
      }
    end
  end

  # POST /auth/oidc/:id/start — POST only, for the same reason the OmniAuth
  # request phase is (CVE-2015-9284): a GET could be triggered on a victim's
  # session from an external page.
  def start
    provider = connectable_provider
    return redirect_to(login_path(error: "oauth_failed")) if provider.nil?

    code_verifier = SecureRandom.urlsafe_base64(64)
    oidc_nonce = SecureRandom.uuid
    state = Auth::State.encode(
      identity_provider_id: provider.id,
      return_to: params[:return_to].presence,
      code_verifier: code_verifier,
      oidc_nonce: oidc_nonce
    )

    redirect_to Auth::Registry.for(provider).authorize_url(
      redirect_uri: callback_url,
      state: state,
      code_challenge: pkce_challenge(code_verifier),
      nonce: oidc_nonce
    ), allow_other_host: true
  rescue Auth::Method::Failure, Auth::Registry::UnsupportedKind
    redirect_to login_path(error: "oauth_failed")
  end

  # GET /auth/oidc/callback — one deployment-wide callback for every connection;
  # which one is carried in the SIGNED state, never in the path.
  def callback
    return redirect_to(login_path(error: "oauth_failed")) if params[:error].present?

    payload = Auth::State.decode(params[:state])
    return redirect_to(login_path(error: "oauth_failed")) if payload.nil?

    side_data = Auth::State.consume(payload["nonce"])
    # nil means replayed or expired. Refusing to exchange the code is the whole
    # point of single-use state.
    return redirect_to(login_path(error: "oauth_failed")) if side_data.nil?

    provider = IdentityProvider.find_by(id: payload["identity_provider_id"])
    return redirect_to(login_path(error: "oauth_failed")) if provider.nil?

    assertion = Auth::Registry.for(provider).complete(
      code: params[:code], redirect_uri: callback_url,
      code_verifier: side_data["code_verifier"], nonce: side_data["oidc_nonce"]
    )
    user = Auth::IdentityResolver.new(assertion).resolve
    return redirect_to(login_path(error: "account_deleted")) if user.deleted?

    enter(user, provider, payload["return_to"])
  rescue Auth::IdentityResolver::NoWorkspaceError
    redirect_to login_path(error: "no_workspace")
  rescue Auth::IdentityResolver::LinkRequiredError
    redirect_to login_path(error: "link_required")
  rescue Auth::IdentityResolver::SuperAdminProviderError
    redirect_to login_path(error: "super_admin_password_only")
  rescue Auth::Method::Failure
    redirect_to login_path(error: "oauth_failed")
  end

  private

  def startable_connections(company)
    allowed = Auth::PolicyResolver.allowed_provider_ids(company)
    company.identity_providers.where(scope: "company", kind: "oidc", id: allowed).order(:id)
  end

  # A connection is startable when its owning company has it enabled — a
  # disabled row must not be reachable by guessing its id.
  def connectable_provider
    # Only kinds that can actually begin a redirect. Anything else would reach
    # an adapter with no #authorize_url and 500 instead of refusing.
    provider = IdentityProvider.where(scope: "company", kind: "oidc").find_by(id: params[:id])
    return nil if provider.nil?
    return nil unless Auth::PolicyResolver.allowed_provider_ids(provider.company).include?(provider.id)

    provider
  end

  def enter(user, provider, return_to)
    # Same append-vs-replace rule as the OmniAuth callback (AD-6): proving a
    # second method inside a live session must not discard the first.
    if signed_in? && current_auth_session&.user_id == user.id
      prove_additional_method(provider)
    else
      sign_in(user, provider: provider)
    end

    session[:current_company_id] = provider.company_id if member_of?(user, provider.company_id)
    redirect_to(safe_return_to(return_to) || company_projects_path)
  end

  def member_of?(user, company_id)
    user.company_memberships.active.exists?(company_id: company_id)
  end

  # Same guard as Web::OauthController#safe_return_to, deliberately identical
  # rather than a narrower re-implementation: control characters are stripped by
  # browsers, turning "/\t/evil.com" into a protocol-relative cross-site
  # redirect, and "/\\host" normalises the same way. A signed state does not
  # make an attacker-supplied destination safe.
  def safe_return_to(value)
    raw = value.to_s
    return nil if raw.blank?
    return nil if raw.match?(/[[:cntrl:]]/)
    return nil unless raw.start_with?("/")
    return nil if raw.start_with?("//", "/\\")

    raw
  end

  # Built as a string rather than through url_for: the redirect_uri must match
  # what the customer registered at their IdP byte for byte, and url_for parses
  # `host` into host+port, which silently drops a port that Settings.domain
  # carries (visible in development, invisible in production until it is not).
  def callback_url
    "#{Settings.protocol}://#{Settings.domain}#{oidc_callback_path}"
  end

  def pkce_challenge(verifier)
    Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(verifier), padding: false)
  end
end
