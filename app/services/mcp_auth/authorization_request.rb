# frozen_string_literal: true

module MCPAuth
  # The parameters of one GET /mcp-oauth/authorize, checked in the order the
  # errors have to be reported (RFC 6749 §4.1.2.1): first who the client is and
  # where it wants the answer — failing either, the error is shown on our page,
  # never redirected — and only then the rest, whose errors go back to the client.
  class AuthorizationRequest
    PARAMS = %w[response_type client_id redirect_uri state code_challenge code_challenge_method scope resource].freeze
    CODE_CHALLENGE_FORMAT = /\A[A-Za-z0-9\-._~]{43,128}\z/

    attr_reader :client, :params, :invalid_client, :error, :error_description

    def initialize(params)
      @params = PARAMS.index_with { |key| params[key].presence&.to_s }.compact
      validate
    end

    def client_valid? = invalid_client.nil?
    def valid? = client_valid? && error.nil?

    def redirect_uri = params["redirect_uri"]
    def code_challenge = params["code_challenge"]
    def resource = params["resource"]&.delete_suffix("/")
    def scope = Endpoints::SCOPE

    def success_redirect(code)
      RedirectUri.with_params(redirect_uri, code: code, state: params["state"], iss: Endpoints.issuer)
    end

    def error_redirect(error = self.error, description = error_description)
      RedirectUri.with_params(redirect_uri, error: error, error_description: description, state: params["state"],
                                            iss: Endpoints.issuer)
    end

    private

    def validate
      @client = Client.resolve(params["client_id"])
      unless RedirectUri.allowed?(client.redirect_uris, redirect_uri)
        raise InvalidClient, "The app asked to return to an address it did not register"
      end

      validate_request
    rescue InvalidClient => e
      @invalid_client = e.message
    end

    def validate_request
      if params["response_type"] != "code"
        fail_with("unsupported_response_type", "Only the authorization code flow is supported")
      elsif params["code_challenge_method"] != "S256" || !CODE_CHALLENGE_FORMAT.match?(code_challenge.to_s)
        fail_with("invalid_request", "A PKCE code_challenge with method S256 is required")
      elsif params["resource"] && !Endpoints.resource?(params["resource"])
        fail_with("invalid_target", "The resource is not an MCP server of this Aixle")
      end
    end

    def fail_with(error, description)
      @error = error
      @error_description = description
    end
  end
end
