# frozen_string_literal: true

module MCP
  # Raised when protected-resource metadata (RFC 9728) or authorization-server
  # metadata (RFC 8414 / OIDC discovery) cannot yield a usable authorization
  # server: an empty/absent authorization_servers list, unparseable metadata, or
  # no discoverable authorization/token endpoints.
  class NoAuthServerError < DiscoveryError; end
end
