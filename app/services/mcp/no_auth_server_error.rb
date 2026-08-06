# frozen_string_literal: true

module MCP
  # Raised when protected-resource metadata (RFC 9728) or authorization-server
  # metadata (RFC 8414 / OIDC discovery) cannot yield a usable authorization
  # server: an empty/absent authorization_servers list, unparseable metadata, or
  # no discoverable authorization/token endpoints.
  class NoAuthServerError < DiscoveryError
    # Distinct from "couldn't connect": we reached the server, it simply does not
    # describe an OAuth authorization server, so retrying will never help.
    def user_message = "This server did not advertise an OAuth authorization server."
  end
end
