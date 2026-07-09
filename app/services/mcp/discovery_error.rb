# frozen_string_literal: true

module MCP
  # Base class for every failure raised while discovering an MCP server's OAuth
  # configuration (RFC 9728 → 8414 → 7591). Callers (Web::OauthController#mcp_connect)
  # rescue this one type and translate it into a generic "couldn't connect" alert —
  # NEVER surfacing the underlying host/metadata to the user or the logs.
  class DiscoveryError < StandardError; end
end
