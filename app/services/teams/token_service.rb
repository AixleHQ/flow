# frozen_string_literal: true

module Teams
  # App-only tokens for the bot: one Bot Connector token from the bot's home
  # tenant, used for every conversation in every tenant (a single-tenant bot on a
  # multi-tenant app, docs/design/teams-integration.md F3), and Graph tokens per
  # customer tenant, which carry that tenant's resource-specific consent.
  #
  # Kept in process memory only: a token lives an hour, each process asks Entra
  # for its own, and none is ever written to the database or the shared cache.
  module TokenService
    # Renew this long before expiry, so a token never runs out mid-request.
    SKEW = 5.minutes

    Token = Data.define(:value, :expires_at)

    @tokens = {}
    @lock = Mutex.new

    class << self
      def bot_token
        token(Config.home_tenant_id, Config.cloud[:bot_scope])
      end

      def graph_token(tenant_id)
        token(tenant_id, "#{Config.cloud[:graph]}/.default")
      end

      # How the bot proves it is itself to a token endpoint: the certificate, or a
      # client secret in development.
      def client_authentication(url)
        return { client_secret: Config.client_secret } unless Config.certificate?

        assertion = Entra::ClientAssertion.new(
          client_id: Config.app_id, private_key: Config.private_key,
          certificate_thumbprint: Config.certificate_thumbprint, token_url: url
        )
        { client_assertion_type: "urn:ietf:params:oauth:client-assertion-type:jwt-bearer", client_assertion: assertion.to_jwt }
      end

      # For a 401 from Microsoft: the cached token is dead even though it looks fresh.
      def forget!(tenant_id = nil)
        @lock.synchronize { tenant_id ? @tokens.delete_if { |(tenant, _), _| tenant == tenant_id } : @tokens.clear }
      end

      private

      def token(tenant_id, scope)
        raise Error, "Teams is not configured" unless Config.enabled?
        raise Error, "not a tenant id: #{tenant_id.inspect}" unless tenant_id.to_s.match?(Config::GUID)

        @lock.synchronize do
          cached = @tokens[[ tenant_id, scope ]]
          return cached.value if cached && cached.expires_at > SKEW.from_now

          @tokens[[ tenant_id, scope ]] = request(tenant_id, scope)
        end.value
      end

      def request(tenant_id, scope)
        url = "#{Config.cloud[:login]}/#{tenant_id}/oauth2/v2.0/token"
        response = Faraday.post(url, URI.encode_www_form(form(url, scope)),
                                "Content-Type" => "application/x-www-form-urlencoded")
        body = JSON.parse(response.body.to_s)
        unless response.success? && body["access_token"].present?
          raise Error.new("Entra refused a token for #{scope}: #{body['error_description'] || body['error']}",
                          status: response.status)
        end

        Token.new(value: body["access_token"], expires_at: body.fetch("expires_in", 3600).to_i.seconds.from_now)
      rescue JSON::ParserError
        raise Error.new("Entra answered the token request with something other than JSON", status: response&.status)
      end

      def form(url, scope)
        { grant_type: "client_credentials", client_id: Config.app_id, scope: scope }.merge(client_authentication(url))
      end
    end
  end
end
