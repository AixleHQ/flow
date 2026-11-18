# frozen_string_literal: true

module MCPAuth
  # POST /mcp-oauth/token: an authorization code, or a refresh token, for a new
  # access + refresh token pair. Every client is public, so the proof that the
  # caller is the one who started the flow is PKCE for a code and possession of
  # the (rotating) refresh token after that.
  class TokenExchange
    class Error < StandardError
      attr_reader :code

      def initialize(code, description)
        @code = code
        super(description)
      end

      def status = code == "invalid_client" ? :unauthorized : :bad_request
    end

    CODE_VERIFIER_FORMAT = /\A[A-Za-z0-9\-._~]{43,128}\z/

    def self.call(params) = new(params).call

    def initialize(params)
      @params = params
    end

    def call
      case @params["grant_type"]
      when "authorization_code" then exchange_code
      when "refresh_token" then refresh
      when nil then raise Error.new("invalid_request", "grant_type is required")
      else raise Error.new("unsupported_grant_type", "Only authorization_code and refresh_token are supported")
      end
    end

    private

    def exchange_code
      code = @params["code"].to_s
      grant = code.start_with?(MCPAuthGrant::CODE_PREFIX) && MCPAuthGrant.find_by(code_digest: MCPAuthGrant.digest(code))
      raise invalid_grant("The authorization code is not valid") unless grant

      # A second use of a code means it leaked: whatever it already bought ends too (RFC 6749 §4.1.2).
      if grant.code_used_at
        grant.revoke!
        raise invalid_grant("The authorization code was already used")
      end
      raise invalid_grant("The authorization code has expired") if grant.code_expired? || grant.revoked?

      check_client!(grant)
      if @params["redirect_uri"].present? && @params["redirect_uri"] != grant.redirect_uri
        raise invalid_grant("redirect_uri does not match the authorization request")
      end
      raise invalid_grant("The code_verifier does not match the code_challenge") unless pkce_verified?(grant)

      unless grant.consume_code!
        grant.revoke!
        raise invalid_grant("The authorization code was already used")
      end

      issue_pair(grant)
    end

    def refresh
      token = MCPAuthToken.find_by_plaintext(@params["refresh_token"], kind: "refresh")
      raise invalid_grant("The refresh token is not valid") unless token

      grant = token.grant
      raise invalid_grant("The refresh token has expired or was revoked") if token.expired? || grant.revoked?

      check_client!(grant)
      unless token.rotate! || token.reload.within_reuse_grace?
        grant.revoke!
        raise invalid_grant("The refresh token was already used; connect the app again")
      end

      issue_pair(grant)
    end

    # A public client sends its client_id with every token request (OAuth 2.1 §3.2.1).
    def check_client!(grant)
      return if @params["client_id"].blank? || @params["client_id"] == grant.client_id

      raise invalid_grant("The token was issued to a different client")
    end

    def pkce_verified?(grant)
      verifier = @params["code_verifier"].to_s
      return false unless CODE_VERIFIER_FORMAT.match?(verifier)

      challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
      ActiveSupport::SecurityUtils.secure_compare(challenge, grant.code_challenge.to_s)
    end

    def issue_pair(grant)
      raise invalid_grant("The account can no longer sign in") unless User.authenticatable.exists?(id: grant.user_id)

      now = Time.current
      access, refresh = MCPAuthGrant.transaction do
        grant.update_columns(expires_at: now + MCPAuthToken::REFRESH_TTL, updated_at: now)
        [ MCPAuthToken.issue!(grant, "access", now: now), MCPAuthToken.issue!(grant, "refresh", now: now) ]
      end

      { access_token: access, token_type: "Bearer", expires_in: MCPAuthToken::ACCESS_TTL.to_i,
        refresh_token: refresh, scope: grant.scope.presence || Endpoints::SCOPE }
    end

    def invalid_grant(description) = Error.new("invalid_grant", description)
  end
end
