# frozen_string_literal: true

module Auth
  module Methods
    # A customer's own OpenID Connect provider, configured per company.
    #
    # Deliberately NOT an OmniAuth strategy: OmniAuth strategies are boot-time
    # initializer constants, and a customer's issuer and client credentials are a
    # database row (AD-4). The flow is built on the `openid_connect` gem, with
    # PKCE and a nonce held server-side by Auth::State.
    class Oidc < Auth::Method
      DISCOVERY_TTL = 12.hours
      DEFAULT_SCOPES = %w[openid email profile].freeze

      class DiscoveryError < Auth::Method::Failure; end

      def authorize_url(redirect_uri:, state:, code_challenge:, nonce:)
        params = {
          client_id: provider.client_id,
          response_type: "code",
          scope: scopes.join(" "),
          redirect_uri: redirect_uri,
          state: state,
          nonce: nonce,
          code_challenge: code_challenge,
          code_challenge_method: "S256"
        }
        uri = URI.parse(discovery.fetch("authorization_endpoint"))
        uri.query = params.to_query
        uri.to_s
      end

      def complete(code:, redirect_uri:, code_verifier:, nonce:)
        tokens = exchange_code(code: code, redirect_uri: redirect_uri, code_verifier: code_verifier)
        claims = verify_id_token!(tokens["id_token"], nonce: nonce)

        Auth::Assertion.new(
          provider: provider,
          # `sub` is the binding claim for OIDC and is never substituted (AD-3).
          subject: claims["sub"].to_s,
          email: claims["email"],
          # Absent is not true: an issuer that does not say so has not verified it.
          email_verified: claims["email_verified"] == true || claims["email_verified"].to_s == "true",
          name: claims["name"] || claims["preferred_username"]
        )
      end

      # The issuer's published metadata, cached: a login must not pay for a
      # discovery round trip, and an issuer must not be hammered once per sign-in.
      def discovery
        @discovery ||= Rails.cache.fetch(discovery_cache_key, expires_in: DISCOVERY_TTL) do
          fetch_json(discovery_url)
        end
      end

      private

      def scopes
        Array(provider.config["scopes"]).presence || DEFAULT_SCOPES
      end

      def discovery_url
        "#{provider.issuer.to_s.chomp('/')}/.well-known/openid-configuration"
      end

      def discovery_cache_key
        "auth_oidc_discovery:#{provider.id}:#{Digest::SHA256.hexdigest(provider.issuer.to_s)}"
      end

      def exchange_code(code:, redirect_uri:, code_verifier:)
        response = Faraday.post(discovery.fetch("token_endpoint")) do |req|
          req.headers["Content-Type"] = "application/x-www-form-urlencoded"
          req.body = {
            grant_type: "authorization_code",
            code: code,
            redirect_uri: redirect_uri,
            client_id: provider.client_id,
            client_secret: provider.client_secret,
            code_verifier: code_verifier
          }.to_query
        end
        raise Auth::Method::Failure, "token endpoint returned #{response.status}" unless response.success?

        JSON.parse(response.body)
      rescue JSON::ParserError
        raise Auth::Method::Failure, "token endpoint returned a non-JSON body"
      end

      # AD-13: the assertion is bound to the row that claims it. `iss` and `aud`
      # are checked against this connection, and the nonce against the one this
      # very request minted — so an id_token issued for another tenant, another
      # client, or another login attempt is refused with no email fallback.
      def verify_id_token!(id_token, nonce:)
        raise Auth::Method::Failure, "no id_token in the token response" if id_token.blank?

        decoded = OpenIDConnect::ResponseObject::IdToken.decode(id_token, jwks)
        decoded.verify!(issuer: provider.issuer, client_id: provider.client_id, nonce: nonce)

        claims = decoded.raw_attributes.merge("sub" => decoded.sub)
        verify_tenant!(claims)
        claims
      rescue JSON::JWT::VerificationFailed, JSON::JWK::Set::KidNotFound => e
        raise Auth::Method::Failure, "id_token signature could not be verified (#{e.class})"
      rescue OpenIDConnect::ResponseObject::IdToken::InvalidToken => e
        raise Auth::Method::Failure, "id_token rejected: #{e.message}"
      end

      # An issuer that multiplexes tenants (Entra behind a generic connection)
      # must still land on the tenant this row names.
      def verify_tenant!(claims)
        expected = provider.tenant_id.to_s
        return if expected.blank?
        return if claims["tid"].to_s == expected

        raise Auth::Method::Failure,
              "id_token tenant #{claims['tid'].inspect} does not match this connection"
      end

      def jwks
        JSON::JWK::Set.new(fetch_json(discovery.fetch("jwks_uri")))
      end

      def fetch_json(url)
        response = Faraday.get(url)
        raise DiscoveryError, "#{url} returned #{response.status}" unless response.success?

        JSON.parse(response.body)
      rescue JSON::ParserError
        raise DiscoveryError, "#{url} returned a non-JSON body"
      end
    end
  end
end
