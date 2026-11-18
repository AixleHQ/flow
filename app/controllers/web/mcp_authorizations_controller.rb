# frozen_string_literal: true

# The authorize step of Aixle's OAuth server for the personal MCP
# (docs/design/mcp-oauth-server.md): an MCP client — Claude, Claude Code,
# Cursor — sends the person here, they sign in if needed and allow or deny it,
# and the browser goes back to the client with a code or an error.
#
# Not per company, so neither the current company's sign-in policy nor its
# onboarding stands in the way: what the grant reaches is decided by the proofs
# of this browser session, and the consent screen lists exactly that.
class Web::MCPAuthorizationsController < Web::ApplicationController
  layout "inertia"

  skip_before_action :enforce_company_auth_policy, :enforce_onboarding

  def new
    authorization = MCPAuth::AuthorizationRequest.new(params)
    return render_page(state: "invalid", message: authorization.invalid_client) unless authorization.client_valid?
    return redirect_out(authorization.error_redirect) unless authorization.valid?

    unless signed_in?
      remember_pending_mcp_authorization(authorization.params)
      return redirect_to(login_path)
    end
    return render_page(state: "impersonating") if impersonated?

    render_consent(authorization)
  end

  def create
    authorization = MCPAuth::AuthorizationRequest.new(params)
    return render_page(state: "invalid", message: authorization.invalid_client) unless authorization.client_valid?
    return redirect_out(authorization.error_redirect) unless authorization.valid?
    return redirect_to(login_path) unless signed_in?
    return render_page(state: "impersonating") if impersonated?

    if params[:decision] != "allow"
      return redirect_out(authorization.error_redirect("access_denied", "The person declined"))
    end

    _grant, code = MCPAuthGrant.authorize!(
      user: current_user, client: authorization.client, redirect_uri: authorization.redirect_uri,
      code_challenge: authorization.code_challenge, resource: authorization.resource, scope: authorization.scope,
      proof_provider_ids: proved_provider_ids
    )
    redirect_out(authorization.success_redirect(code))
  end

  private

  # Back to the client, on another host or in a native app. An Inertia visit is
  # an XHR, which cannot follow that, so it is told to navigate instead.
  def redirect_out(url)
    request.headers["X-Inertia"].present? ? inertia_location(url) : redirect_to(url, allow_other_host: true)
  end

  def render_consent(authorization)
    reachable = Company.where(id: reachable_company_ids).order(:name).pluck(:name)
    excluded = Company.where(id: current_user.company_memberships.active.select(:company_id))
                      .where.not(id: reachable_company_ids).order(:name).pluck(:name)
    client = authorization.client

    render_page(
      state: reachable.empty? ? "no_company" : "ready",
      client: { name: client.name, host: client.host, label: client.label, verified: client.host.present? },
      destination: MCPAuth::RedirectUri.destination(authorization.redirect_uri),
      on_this_computer: MCPAuth::RedirectUri.on_this_computer?(authorization.redirect_uri),
      account: { name: current_user.name, email: current_user.email },
      companies: reachable,
      excluded_companies: excluded,
      authorize_url: mcp_oauth_authorize_path,
      authorize_params: authorization.params
    )
  end

  def render_page(state:, **props)
    render inertia: "Integrations/McpAuthorize", props: { state: state, **props }
  end

  def proved_provider_ids
    current_user_session&.proved_provider_ids || []
  end

  def reachable_company_ids
    @reachable_company_ids ||= Auth::PolicyResolver.satisfied_company_ids(
      company_ids: current_user.company_memberships.active.select(:company_id),
      provider_ids: proved_provider_ids
    ).to_a
  end
end
