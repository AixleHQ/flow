# frozen_string_literal: true

# Browser OAuth for Codex credentials in hosted Aixle deployments. Unlike the
# Codex CLI's loopback server, this flow returns to the deployment's public host
# and persists the resulting auth.json material directly for the acting user and
# company.
class Web::CodexOauthController < Web::ApplicationController
  SCOPE = "openid profile email offline_access api.connectors.read api.connectors.invoke"

  before_action :require_auth
  skip_before_action :redirect_super_admin_to_admin_panel, raise: false

  def authorize
    return redirect_to(profile_path, alert: "Codex authentication is not configured") if client_id.blank?
    return redirect_to(profile_path, alert: "Select a company before authenticating Codex") unless current_company

    verifier = SecureRandom.urlsafe_base64(64)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    state = Oauth::State.encode(
      owner_type: "Company",
      owner_id: current_company.id,
      user_id: current_user.id,
      provider: "codex",
      return_to: profile_path,
      code_verifier: verifier
    )

    redirect_to authorization_url(state:, challenge:), allow_other_host: true
  end

  def callback
    payload = Oauth::State.decode(params[:state])
    return oauth_error("Invalid or expired Codex authorization") unless valid_payload?(payload)

    if params[:error].present?
      return oauth_error(provider_error_message(params[:error]))
    end

    consumed = Oauth::State.consume(payload["nonce"])
    return oauth_error("This Codex authorization link was already used or expired") unless consumed
    return oauth_error("Codex authorization did not match your session") unless consumed["user_id"] == current_user.id

    company = current_user.company_memberships.active.find_by(company_id: payload["owner_id"])&.company
    return oauth_error("You no longer have access to that company") unless company
    return oauth_error("Codex did not return an authorization code") if params[:code].blank?

    tokens = Codex::Api.exchange_authorization_code(
      code: params[:code].to_s,
      code_verifier: consumed["code_verifier"],
      redirect_uri: redirect_uri,
      client_id: client_id
    )
    raise Codex::Api::ParseError, "authorization_code returned no access token" if tokens.access_token.blank?

    credential = AgentCredential.from_artifacts(
      current_user.id,
      company.id,
      "codex",
      {
        "tokens" => {
          "access_token" => tokens.access_token,
          "refresh_token" => tokens.refresh_token,
          "id_token" => tokens.id_token
        }.compact,
        "last_refresh" => Time.current.iso8601
      },
      new_authorization: true
    )
    membership = current_user.company_memberships.active.find_by(company_id: company.id)
    membership.update!(default_agent_credential: credential) if membership&.default_agent_credential_id.nil?

    redirect_to profile_path, notice: "Codex authentication saved"
  rescue Codex::Api::ApiError => e
    Rails.logger.warn("[CodexOauth] token exchange failed: #{e.class.name}")
    oauth_error("Codex could not complete authentication. Please try again.")
  end

  private

  def require_auth
    redirect_to login_path unless signed_in?
  end

  def valid_payload?(payload)
    payload && payload["provider"] == "codex" && payload["user_id"] == current_user.id
  end

  def client_id
    Settings.codex_oauth.client_id.to_s.presence
  end

  def redirect_uri
    "#{Settings.protocol}://#{Settings.domain}/auth/codex/callback"
  end

  def authorization_url(state:, challenge:)
    query = URI.encode_www_form(
      response_type: "code",
      client_id: client_id,
      redirect_uri: redirect_uri,
      scope: SCOPE,
      code_challenge: challenge,
      code_challenge_method: "S256",
      id_token_add_organizations: "true",
      codex_cli_simplified_flow: "true",
      state: state,
      originator: "aixle"
    )
    "#{Settings.codex_oauth.issuer.to_s.chomp('/')}/oauth/authorize?#{query}"
  end

  def provider_error_message(error)
    case error.to_s
    when "access_denied" then "Codex authorization was cancelled or denied"
    when "temporarily_unavailable" then "Codex authentication is temporarily unavailable"
    else "Codex authentication failed at the provider"
    end
  end

  def oauth_error(message)
    redirect_to profile_path, alert: message
  end
end
