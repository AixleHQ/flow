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

  # POST /login/identify — step one of signing in. The person gives an address
  # and nothing else; what comes back is decided by the address's DOMAIN, which
  # already resolves to exactly one company.
  #
  # Never by whether an account exists: an unknown address at a known domain
  # must answer exactly as a known one does, or the screen becomes an oracle
  # for which addresses are registered.
  def identify
    email = params[:email].to_s.strip
    return redirect_to(login_path(error: "invalid_email")) unless email.match?(URI::MailTo::EMAIL_REGEXP)

    options = Auth::SignInOptions.for(email)
    return redirect_to(login_path(error: "no_workspace")) if options.nil?

    case options.connections.size
      # Begun right here rather than redirected to #start: that route is POST
      # only (CVE-2015-9284) and a redirect is followed with GET, so handing it
      # the single connection answered with a routing error instead of a
      # sign-in. This request is already the person's own POST, carrying their
      # CSRF token, so there is nothing a second hop would add.
    when 1 then begin_authorization(options.connections.first, company: options.company)
    when 0 then render_credentials_step(email, options)
    else
      # More than one: let them choose rather than guessing on their behalf.
      render inertia: "Auth/SsoChoicePage", props: {
        company_name: options.company.branded_name,
        connections: options.connections.map { |c| { id: c.id, name: c.display_name } }
      }
    end
  end

  # POST /auth/oidc/:id/start — POST only, for the same reason the OmniAuth
  # request phase is (CVE-2015-9284): a GET could be triggered on a victim's
  # session from an external page.
  def start
    provider = connectable_provider
    return redirect_to(login_path(error: "oauth_failed")) if provider.nil?

    begin_authorization(provider, company: provider.company)
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

  # Step two, for a workspace that does not sign in through a provider: the same
  # login screen, told which address it is for and which methods this workspace
  # actually accepts. Nothing it cannot complete is ever drawn.
  def render_credentials_step(email, options)
    render inertia: "Auth/LoginPage", props: {
      step: "credentials",
      email: email,
      company_name: options.company.branded_name,
      # Intersected with what this INSTALLATION offers, so a company policy can
      # never conjure a method the deployment has no credentials for (AD-4).
      methods: options.kinds & Auth::PolicyResolver.deployment_allowlist_kinds,
      dead_end: options.dead_end?
    }
  end

  # Sends the browser to the provider. Shared by #start and #identify so the two
  # ways of reaching a connection cannot drift apart.
  def begin_authorization(provider, company:)
    code_verifier = SecureRandom.urlsafe_base64(64)
    oidc_nonce = SecureRandom.uuid
    state = Auth::State.encode(
      identity_provider_id: provider.id,
      return_to: return_to_for(provider, company),
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

  # A connection is startable when its owning company has it enabled — a
  # disabled row must not be reachable by guessing its id.
  def connectable_provider
    # Only kinds that can actually begin a redirect. Anything else would reach
    # an adapter with no #authorize_url and 500 instead of refusing.
    provider = IdentityProvider.where(scope: "company", kind: "oidc").find_by(id: params[:id])
    return nil if provider.nil?
    return provider if Auth::PolicyResolver.accepts?(company: provider.company, provider: provider)
    return provider if verifying_own_connection?(provider)

    nil
  end

  # AD-7 requires a connection to be proved before it can be enabled, and the
  # proof is a real sign-in through it. Refusing to START a disabled connection
  # made that impossible: no sign-in without enabling, no enabling without a
  # sign-in, and only a platform operator could break the cycle. An admin of the
  # owning company may therefore start one that is still switched off.
  #
  # It stays a verification, not a way in: the company still does not accept the
  # method, so the entry gate turns the resulting session away exactly as before.
  # A verification lands back on the screen that asked for it, where the
  # connection can now be switched on.
  # Takes the company rather than reading provider.company: in #identify the
  # provider comes out of a multi-row fetch, and loading its company there is
  # the N+1 Bullet refuses.
  def return_to_for(provider, company)
    return company_settings_access_path unless Auth::PolicyResolver.accepts?(company: company, provider: provider)

    params[:return_to].presence
  end

  def verifying_own_connection?(provider)
    return false unless signed_in?

    current_user.company_memberships.active.exists?(company_id: provider.company_id, role: "admin")
  end

  def enter(user, provider, return_to)
    sign_in_or_prove(user, provider: provider)

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

  # Built as a string rather than through url_for: this value must match what the
  # customer registered at their IdP byte for byte, and it must not vary with the
  # request. url_for in a controller derives the host from the incoming request,
  # so a proxy header or a direct hit on the container would produce a different
  # redirect_uri than the one the IdP knows — and the token exchange sends it
  # again, where a mismatch is a hard refusal.
  def callback_url
    "#{Settings.protocol}://#{Settings.domain}#{oidc_callback_path}"
  end

  def pkce_challenge(verifier)
    Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(verifier), padding: false)
  end
end
