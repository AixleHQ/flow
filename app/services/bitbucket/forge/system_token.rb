# frozen_string_literal: true

module Bitbucket
  module Forge
    # The app token Forge pushes in `x-forge-oauth-system`. Forge calls it
    # opaque; it is a JWT today, and its `exp` is the only thing read from it —
    # never trusted for identity, which comes from the invocation token.
    module SystemToken
      module_function

      # When the token expires, or nil when that cannot be read.
      def expires_at(token)
        payload = token.to_s.split(".")[1]
        return if payload.blank?

        claims = JSON.parse(Base64.urlsafe_decode64(payload + ("=" * (-payload.length % 4))))
        exp = claims["exp"] if claims.is_a?(Hash)
        Time.zone.at(exp) if exp.is_a?(Numeric)
      rescue ArgumentError, JSON::ParserError
        nil
      end
    end
  end
end
