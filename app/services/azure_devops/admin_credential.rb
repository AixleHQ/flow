# frozen_string_literal: true

module AzureDevops
  # What the person connecting an organization proves they administer it with:
  # a Microsoft sign-in (a delegated Azure DevOps token) or a personal access
  # token. It lives for one onboarding and is never stored.
  AdminCredential = Data.define(:kind, :secret, :claims) do
    def self.pat(token)
      new(kind: :pat, secret: token.to_s, claims: {}) if token.present?
    end

    # The token came from Entra's token endpoint over TLS to us, its client;
    # its claims are read, not verified.
    def self.sign_in(access_token)
      payload = access_token.to_s.split(".")[1].to_s
      claims = JSON.parse(Base64.urlsafe_decode64(payload + ("=" * ((4 - (payload.length % 4)) % 4))))
      new(kind: :sign_in, secret: access_token.to_s, claims: claims)
    rescue JSON::ParserError, ArgumentError
      raise Error.new("Microsoft returned a token that could not be read", code: "unexpected_token")
    end

    def pat? = kind == :pat
    def sign_in? = kind == :sign_in

    # Azure DevOps takes a PAT as Basic with an empty user name.
    def authorization
      pat? ? "Basic #{Base64.strict_encode64(":#{secret}")}" : "Bearer #{secret}"
    end

    def tenant_id = claims["tid"]
    def identity = claims["upn"].presence || claims["preferred_username"].presence || claims["unique_name"].presence
    def describe = pat? ? "personal access token" : "Microsoft sign-in"

    def inspect = "#<AzureDevops::AdminCredential #{kind}>"
  end
end
