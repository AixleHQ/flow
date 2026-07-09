# frozen_string_literal: true

module Oauth
  # Raised inside the OAuth callback when the authorization-code exchange fails
  # (non-2xx response, unreachable host, or unparseable body). Its message carries
  # only a class name or HTTP status code — NEVER token material or the code — so it
  # is always safe to log.
  class TokenExchangeError < StandardError; end
end
