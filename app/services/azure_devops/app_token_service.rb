# frozen_string_literal: true

module AzureDevops
  # App-only (client-credentials) access tokens for one approved installation.
  #
  # This is NOT the delegated OAuth path. Oauth::TokenService and OauthCredential
  # implement refresh-token grants for tokens minted on behalf of a user; there
  # is no refresh token here at all. "Renew" means "ask Entra again with the
  # app's own credential", which is why a 401 can safely trigger exactly one
  # reacquisition and one retry instead of a re-consent prompt.
  #
  # Entra tokens for this resource live about an hour, so every long session
  # passes through here; the cache and the lock exist for that traffic, not for a
  # rare edge case.
  class AppTokenService
    # Entra will not issue a token for a tenant id we did not validate, but the
    # value also goes into a URL path, so it is checked before it is used.
    GUID = /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/

    Token = Struct.new(:value, :expires_at, keyword_init: true) do
      def expires_in = [ (expires_at - Time.current).to_i, 0 ].max
    end

    def initialize(installation)
      @installation = installation
      @app = AppConfig.fetch(installation.app_config_key)
    end

    attr_reader :installation, :app

    # Returns a usable Token, from cache when one is live.
    #
    # `force` skips the cache after a 401 — the caller has evidence the cached
    # value is dead, which the expiry alone does not show (a revoked principal
    # or a rotated credential both look fresh until Azure refuses them).
    def access_token(force: false)
      app.validate!

      unless force
        cached = read_cache
        return cached if cached
      end

      with_lock do
        # Someone else may have renewed while we waited for the lock. Re-read
        # rather than minting a second token and racing the write.
        cached = read_cache unless force
        next cached if cached

        acquire_and_cache!
      end
    end

    # A 401 from Azure invalidates the cached token and buys exactly one retry.
    # More than one would turn a revoked principal into a request loop.
    def refresh_after_unauthorized!
      installation.clear_token_cache!
      access_token(force: true)
    end

    private

    def read_cache
      installation.reload if installation.persisted?
      return nil unless installation.token_usable?(
        generation: app.credential_generation,
        resource: AppConfig.resource,
        skew: AppConfig.token_refresh_skew
      )

      value = installation.cached_access_token
      return nil if value.blank?

      Token.new(value: value, expires_at: installation.token_expires_at)
    end

    def acquire_and_cache!
      payload = request_token!

      expires_at = Time.current + payload.fetch("expires_in", 3600).to_i.seconds
      installation.cached_access_token = payload.fetch("access_token")
      installation.assign_attributes(
        token_expires_at: expires_at,
        token_credential_generation: app.credential_generation,
        token_resource: AppConfig.resource
      )
      installation.save!(validate: false)

      Token.new(value: payload.fetch("access_token"), expires_at: expires_at)
    end

    def request_token!
      tenant = installation.tenant_id.to_s
      raise NotAuthorized, "Installation tenant is not a GUID" unless tenant.match?(GUID)

      response = connection.post("/#{tenant}/oauth2/v2.0/token") do |req|
        req.headers["Content-Type"] = "application/x-www-form-urlencoded"
        req.body = URI.encode_www_form(token_params)
      end

      parse_token_response!(response)
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      # A transport failure is not a credential failure. Saying
      # credential_action_required here would send an operator rotating a
      # perfectly good certificate because a DNS lookup blipped.
      raise Error.new("Azure token endpoint unreachable: #{e.class}", code: "token_endpoint_unreachable")
    end

    def token_params
      base = {
        grant_type: "client_credentials",
        client_id: app.client_id,
        scope: AppConfig.resource
      }

      case app.credential_kind
      when :certificate
        base.merge(
          client_assertion_type: "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
          client_assertion: ClientAssertion.new(app: app, tenant_id: installation.tenant_id).to_jwt
        )
      when :client_secret
        base.merge(client_secret: app.client_secret)
      else
        raise CredentialActionRequired, "No usable Azure DevOps app credential"
      end
    end

    def parse_token_response!(response)
      body = begin
        JSON.parse(response.body.to_s)
      rescue JSON::ParserError
        {}
      end

      return body if response.status == 200 && body["access_token"].present?

      # Entra's own error codes, not the HTTP status, distinguish "this app's
      # credential is bad" from "this tenant has not provisioned the app".
      code = body["error"].to_s
      description = body["error_description"].to_s.split("\n").first.to_s

      if %w[invalid_client unauthorized_client].include?(code)
        raise CredentialActionRequired,
              "Azure rejected the application credential (#{code}): #{description}"
      end

      raise NotAuthorized,
            "Azure did not issue an app token for tenant #{installation.tenant_id} (#{code.presence || response.status}): #{description}"
    end

    def connection
      @connection ||= Faraday.new(url: AppConfig.login_host) do |f|
        f.options.open_timeout = AppConfig.open_timeout
        f.options.timeout = AppConfig.read_timeout
        f.adapter Faraday.default_adapter
      end
    end

    # Advisory lock rather than a row lock: the point is to stop N session
    # containers from minting N tokens at the same moment, and the row is also
    # read by the authorization path, which must not block behind a token call.
    def with_lock(&)
      return yield unless installation.persisted?

      installation.with_lock(&)
    end
  end
end
