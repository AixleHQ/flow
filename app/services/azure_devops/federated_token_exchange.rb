# frozen_string_literal: true

module AzureDevops
  # Trades the assertion this deployment signs for an access token of a
  # customer-owned Entra app, which trusts us through a federated credential.
  #
  # No secret is involved on either side: Entra verifies the assertion against
  # the keys this deployment publishes (FederationConfig), checks `iss`, `sub`
  # and `aud` against the credential the customer created, and answers with a
  # token for THEIR app. Holds no state; AppTokenService caches the result.
  class FederatedTokenExchange
    GUID = /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/
    CLIENT_ASSERTION_TYPE = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"

    # What a customer can act on, by Entra's own error code. Only codes Microsoft
    # documents are named; anything else gets the checklist below, with Entra's
    # own words, rather than a guess.
    HINTS = {
      "700213" => "No federated credential on the app matches this connection's subject. Copy the subject " \
                  "from Flow exactly: Entra compares it case-sensitively and accepts a mistyped one when it " \
                  "is saved.",
      "700016" => "The app was not found in this directory. Check the client ID and the tenant.",
      "7000112" => "The app is disabled in this directory."
    }.freeze

    CHECKLIST = "Check the federated credential on the app: its issuer, subject and audience must match " \
                "exactly what Flow shows, and the client ID must belong to an app in this directory."

    def self.call(**) = new(**).call

    def initialize(tenant_id:, client_id:, company:)
      @tenant_id = tenant_id.to_s
      @client_id = client_id.to_s
      @company = company
    end

    # The token endpoint's JSON on success (`access_token`, `expires_in`).
    def call
      raise NotAuthorized, "Tenant is not a GUID" unless @tenant_id.match?(GUID)
      raise ValidationFailed, "The client ID must be the app's Application (client) ID, a GUID" unless @client_id.match?(GUID)
      unless FederationConfig.enabled?
        raise CredentialActionRequired, "Azure DevOps federation is not configured on this deployment"
      end

      response = connection.post("/#{@tenant_id}/oauth2/v2.0/token") do |req|
        req.headers["Content-Type"] = "application/x-www-form-urlencoded"
        req.body = URI.encode_www_form(params)
      end

      parse!(response)
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      raise Error.new("Azure token endpoint unreachable: #{e.class}", code: "token_endpoint_unreachable")
    rescue Entra::FederatedAssertion::InvalidCredential => e
      raise CredentialActionRequired, "Azure DevOps federation #{e.message}"
    end

    private

    def params
      {
        grant_type: "client_credentials",
        client_id: @client_id,
        scope: AppConfig.resource,
        client_assertion_type: CLIENT_ASSERTION_TYPE,
        client_assertion: assertion
      }
    end

    def assertion
      key = FederationConfig.signing_key!
      Entra::FederatedAssertion.new(
        issuer: FederationConfig.issuer_url,
        subject: FederatedSubject.for(@company),
        audience: FederationConfig.audience,
        private_key: key,
        key_id: FederationConfig.key_id(key)
      ).to_jwt
    end

    def parse!(response)
      body = begin
        JSON.parse(response.body.to_s)
      rescue JSON::ParserError
        {}
      end
      return body if response.status == 200 && body["access_token"].present?

      code = body["error"].to_s
      description = body["error_description"].to_s.split("\n").first.to_s
      aadsts = description[/AADSTS(\d+)/, 1]

      if %w[invalid_client unauthorized_client].include?(code) || HINTS.key?(aadsts)
        hint = HINTS.fetch(aadsts, CHECKLIST)
        raise FederationRejected.new(
          "Microsoft Entra did not accept Flow's identity for this app (#{aadsts ? "AADSTS#{aadsts}" : code}). #{hint}",
          details: description.presence
        )
      end

      raise NotAuthorized,
            "Azure did not issue an app token for tenant #{@tenant_id} (#{code.presence || response.status}): #{description}"
    end

    def connection
      @connection ||= Faraday.new(url: AppConfig.login_host) do |f|
        f.options.open_timeout = AppConfig.open_timeout
        f.options.timeout = AppConfig.read_timeout
        f.adapter Faraday.default_adapter
      end
    end
  end
end
