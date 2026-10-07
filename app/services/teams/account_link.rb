# frozen_string_literal: true

module Teams
  # Tying a Teams sender to the Aixle account of the person signed in
  # (docs/design/teams-integration.md §9, §20). The bot hands the sender a link
  # naming their Teams account; it completes only after a Microsoft sign-in, at
  # the conversation's own tenant, as that very account. A link forwarded to
  # someone else therefore proves nothing.
  module AccountLink
    class Refused < StandardError; end

    TTL = 1.hour
    PROOF = "microsoft_sign_in"
    SCOPE = "openid profile"
    STATE_PROVIDER = "teams_link"

    module_function

    def url_for(integration:, tenant_id:, object_id:)
      token = verifier.generate({ "integration_id" => integration.id, "tid" => tenant_id, "oid" => object_id },
                                expires_in: TTL, purpose: :teams_account_link)
      "#{Settings.protocol}://#{Settings.domain}/integrations/teams/link/#{token}"
    end

    # The sender a link names, or nil when it is forged or expired.
    def claim(token)
      verifier.verified(token.to_s, purpose: :teams_account_link)
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError
      nil
    end

    def integration_for(claim)
      Integration.active.find_by(id: claim.to_h["integration_id"], provider: Connection::PROVIDER)
                 .then { |integration| integration if integration&.settings.to_h["tenant_id"] == claim["tid"] }
    end

    def member?(user, integration)
      user.company_memberships.active.exists?(company_id: integration.company_id)
    end

    # A guest's home-tenant sign-in carries another object id than the one Teams
    # reports for them, so the sign-in happens at the conversation's tenant.
    def authorize_url(claim, user)
      code_verifier = SecureRandom.urlsafe_base64(48)
      state = ::Oauth::State.encode(owner_type: "User", owner_id: user.id, user_id: user.id, return_to: nil,
                                    code_verifier: code_verifier, provider: STATE_PROVIDER,
                                    context: claim.slice("integration_id", "tid", "oid"))
      query = URI.encode_www_form(
        client_id: Config.app_id, response_type: "code", redirect_uri: Connection.redirect_uri, response_mode: "query",
        scope: SCOPE, state: state, prompt: "select_account",
        code_challenge: Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false),
        code_challenge_method: "S256"
      )
      "#{Config.cloud[:login]}/#{claim['tid']}/oauth2/v2.0/authorize?#{query}"
    end

    def complete!(user:, state:, code:, code_verifier:)
      context = state["context"].to_h
      raise Refused, "This link was opened in another Aixle session. Open it again." unless state["owner_id"] == user.id

      integration = integration_for(context)
      raise Refused, "This Microsoft 365 organization is no longer connected to Aixle." if integration.nil?
      raise Refused, "You are not a member of #{integration.company.name} in Aixle." unless member?(user, integration)

      claims, = Connection.sign_in_claims(code, code_verifier, SCOPE, authority: context["tid"])
      unless claims["tid"] == context["tid"] && claims["oid"] == context["oid"]
        raise Refused, "That Microsoft account is not the Teams account that asked for this link. " \
                       "Sign in as the person the link was sent to."
      end

      identity = ChatIdentity.find_or_initialize_by(provider: Chat::TeamsProvider::KEY, workspace_id: context["tid"],
                                                    external_user_id: context["oid"])
      identity.update!(user: user, proof: PROOF, linked_at: Time.current)
      identity
    rescue Connection::Refused => e
      raise Refused, e.message
    end

    def verifier = Rails.application.message_verifier("teams_account_link")
  end
end
