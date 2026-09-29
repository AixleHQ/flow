# frozen_string_literal: true

module MCP
  # Raised when discovered OAuth metadata does not describe the server it was
  # fetched for: protected-resource metadata naming another resource (RFC 9728
  # §3.3), authorization-server metadata naming another issuer (RFC 8414 §3.3), or
  # a consent page on a site that is neither the issuer's nor the MCP server's.
  # The last is the mix-up that lets a server send the user to a real provider
  # while keeping the token endpoint — and the code — for itself.
  class MetadataMismatchError < DiscoveryError
    def user_message = "This server's OAuth metadata does not match its address, so it was not trusted."
  end
end
