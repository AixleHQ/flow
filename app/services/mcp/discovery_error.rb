# frozen_string_literal: true

module MCP
  # Base class for every failure raised while discovering an MCP server's OAuth
  # configuration (RFC 9728 → 8414 → 7591). Callers (Web::OauthController#mcp_connect)
  # rescue this one type and show #user_message.
  #
  # A user-facing message is always one of OUR sentences, selected by a value the
  # raising subclass has allowlisted — upstream text is NEVER echoed. Every input in
  # this flow is attacker-authored (pasted MCP url, WWW-Authenticate header, RFC
  # 9728/8414/7591 JSON), so an authorization server must not be able to put its own
  # words in front of a user or into our logs.
  class DiscoveryError < StandardError
    GENERIC = "Couldn't connect to this MCP server"

    # A short allowlisted machine code, for the log line and for message selection.
    # nil unless a subclass recognised one.
    attr_reader :code

    def initialize(message = nil, code: nil)
      super(message)
      @code = code
    end

    # Deliberately vague: "we could not talk to it" is all we can honestly say about
    # a transport failure, and all we are willing to say about an SSRF rejection.
    def user_message = GENERIC
  end
end
