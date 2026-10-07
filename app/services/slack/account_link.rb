# frozen_string_literal: true

module Slack
  # Tying a Slack sender to the Aixle account of the person signed in
  # (docs/design/teams-integration.md §21). The bot hands the sender a link naming
  # their Slack account; it completes only after Sign in with Slack, in that
  # workspace, as that very account. A link forwarded to someone else proves nothing.
  module AccountLink
    class Refused < StandardError; end

    TTL = 1.hour
    PROOF = "slack_sign_in"
    SCOPE = "openid profile"
    STATE_PROVIDER = "slack_link"
    AUTHORIZE_URL = "https://slack.com/openid/connect/authorize"
    TEAM_CLAIM = "https://slack.com/team_id"
    USER_CLAIM = "https://slack.com/user_id"

    module_function

    def url_for(integration:, team_id:, user_id:)
      token = verifier.generate({ "integration_id" => integration.id, "team" => team_id, "user" => user_id },
                                expires_in: TTL, purpose: :slack_account_link)
      "#{Settings.protocol}://#{Settings.domain}/integrations/slack/link/#{token}"
    end

    # The sender a link names, or nil when it is forged or expired.
    def claim(token)
      verifier.verified(token.to_s, purpose: :slack_account_link)
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError
      nil
    end

    def integration_for(claim)
      Integration.active.find_by(id: claim.to_h["integration_id"], provider: :slack)
                 .then { |integration| integration if integration&.settings.to_h["team_id"] == claim["team"] }
    end

    def member?(user, integration)
      user.company_memberships.active.exists?(company_id: integration.company_id)
    end

    # A subdirectory of the install's redirect URL, which Slack accepts without
    # registering another one.
    def redirect_uri = "#{Oauth.redirect_uri}/link"

    def authorize_url(claim, user)
      nonce = SecureRandom.urlsafe_base64(24)
      state = ::Oauth::State.encode(owner_type: "User", owner_id: user.id, user_id: user.id, return_to: nil,
                                    code_verifier: nonce, provider: STATE_PROVIDER,
                                    context: claim.slice("integration_id", "team", "user"))
      query = URI.encode_www_form(response_type: "code", scope: SCOPE, client_id: Settings.slack.client_id,
                                  redirect_uri: redirect_uri, state: state, nonce: nonce, team: claim["team"])
      "#{AUTHORIZE_URL}?#{query}"
    end

    # The ID token comes straight from Slack's token endpoint over TLS, for a code
    # only this app's secret can redeem, so its claims are Slack's (OpenID Connect
    # Core §3.1.3.7); what is still checked is that it is ours, current, and this sign-in's.
    def complete!(user:, state:, code:, nonce:)
      context = state["context"].to_h
      raise Refused, "This link was opened in another Aixle session. Open it again." unless state["owner_id"] == user.id

      integration = integration_for(context)
      raise Refused, "This Slack workspace is no longer connected to Aixle." if integration.nil?
      raise Refused, "You are not a member of #{integration.company.name} in Aixle." unless member?(user, integration)

      claims = sign_in_claims(code, nonce)
      unless claims[TEAM_CLAIM] == context["team"] && claims[USER_CLAIM] == context["user"]
        raise Refused, "That Slack account is not the one that asked for this link. Sign in as the person it was sent to."
      end

      identity = ChatIdentity.find_or_initialize_by(provider: Chat::SlackProvider::KEY, workspace_id: context["team"],
                                                    external_user_id: context["user"])
      identity.update!(user: user, proof: PROOF, linked_at: Time.current)
      identity
    end

    def sign_in_claims(code, nonce)
      body = Client.openid_token(code: code.to_s, redirect_uri: redirect_uri)
      claims = JWT.decode(body["id_token"].to_s, nil, false).first
      raise Refused, "The sign-in was issued to another application" unless claims["aud"] == Settings.slack.client_id
      raise Refused, "The sign-in has expired" if claims["exp"].to_i < Time.current.to_i
      raise Refused, "The sign-in does not belong to this link" unless nonce.present? && claims["nonce"] == nonce

      claims
    rescue Client::Error => e
      raise Refused, "Slack did not complete the sign-in: #{e.message}"
    rescue JWT::DecodeError
      raise Refused, "Slack answered the sign-in with an unreadable token"
    end

    def verifier = Rails.application.message_verifier("slack_account_link")
  end
end
