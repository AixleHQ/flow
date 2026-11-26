# frozen_string_literal: true

module AwsOidc
  # STS fetched the keys but rejected the token: no provider for this issuer in the
  # account, the audience missing on it, or a signature it could not verify.
  class IdentityTokenError < Error; end
end
