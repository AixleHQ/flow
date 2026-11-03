# frozen_string_literal: true

module AzureDevops
  # Reads claims out of an app-only access token Entra has just issued to us.
  # Reading is not validation: we are the audience and received it over TLS
  # straight from Entra, so the signature is not re-checked.
  module TokenClaims
    module_function

    # The service principal's object id in the tenant that issued the token,
    # which is what Azure DevOps entitlement and permission APIs take.
    def object_id!(token)
      payload = token.to_s.split(".")[1].to_s
      claims = JSON.parse(Base64.urlsafe_decode64(payload + ("=" * ((4 - (payload.length % 4)) % 4))))
      oid = claims["oid"].presence
      raise Error.new("Entra issued a token without an oid claim", code: "unexpected_token") if oid.blank?

      oid
    rescue JSON::ParserError, ArgumentError
      raise Error.new("Could not read the application's identity from its token", code: "unexpected_token")
    end
  end
end
