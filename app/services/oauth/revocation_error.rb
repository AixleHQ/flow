# frozen_string_literal: true

module Oauth
  # Raised when a provider does not confirm the revocation of a grant (non-2xx
  # response, unreachable host, or no revocation endpoint). Its message carries only a
  # class name or HTTP status code, never token material, so it is safe to log.
  class RevocationError < StandardError; end
end
