# frozen_string_literal: true

# Credential-vending endpoint for the in-container Git credential helper.
#
# Modelled directly on CloudCredentialsController: same "only a live session
# vends" rule, same derived per-session key, and the same deliberate decision NOT
# to authenticate with the session's `mcp_key` — that key is handed into the
# container as the aixle-tools MCP header, so the agent-driven process already
# holds it, and it has a disable endpoint whose revocation would then also stop
# `git push` working. See AzureDevops::GitSessionKey.
#
# This is not an MCP tool and is not in any tool list: the helper posts here, the
# response goes straight into Git's credential protocol pipe, and nothing about
# it reaches the model's context by design. The honest limit is stated in the
# design's §7 credential boundary — the session process necessarily receives
# usable Git authentication, and a service-principal token is bound to the
# tenant and application rather than to one organization.
class AzureGitCredentialsController < ActionController::API
  def create
    session = TerminalSession.find_by(id: request.headers["X-Session-Id"])
    return unauthorized unless session&.active?
    return unauthorized unless AzureDevops::GitSessionKey.valid?(session, request.headers["X-Azure-Git-Key"])

    vended = AzureDevops::GitCredentialService.new(session).vend!(
      repository_id: params[:repository_id],
      requested_url: params[:url]
    )

    # no-store so nothing between here and the helper keeps a copy, and an
    # explicit content type because the helper parses the body directly.
    response.set_header("Cache-Control", "no-store")
    render json: vended.to_h, content_type: "application/json"
  rescue AzureDevops::NotAuthorized, AzureDevops::IntegrationUnavailable => e
    deny(session, e, :forbidden)
  rescue AzureDevops::CredentialActionRequired => e
    # An operator problem, not a user one. The helper surfaces this as a failed
    # authentication rather than prompting anybody to sign in.
    deny(session, e, :service_unavailable)
  rescue AzureDevops::Error => e
    deny(session, e, :bad_gateway)
  end

  private

  # Logged here on purpose: the helper's stderr is swallowed by Git, so this is
  # the only place a broken credential request is visible. The message is an
  # adapter error code, never a provider body and never a token.
  def deny(session, error, status)
    Rails.logger.warn(
      "[AzureGitCredentials] session=#{session&.id} repository=#{params[:repository_id]} " \
      "denied=#{error.code}"
    )
    render json: { error: error.code, message: error.message }, status: status
  end

  def unauthorized
    Rails.logger.warn("[AzureGitCredentials] rejected an unauthenticated credential request")
    render json: { error: "unauthorized" }, status: :unauthorized
  end
end
