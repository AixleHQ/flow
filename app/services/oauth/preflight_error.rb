# frozen_string_literal: true

module Oauth
  # Raised at session-start when required OAuth MCP connections are missing or dead
  # (oauth-unification §4.6). Carries the servers still needing a connection — each
  # with a Connect URL — so the API blocks the launch with a "Connect …" CTA instead
  # of starting a session that would fail silently during provisioning.
  class PreflightError < StandardError
    attr_reader :connections

    def initialize(connections)
      @connections = connections
      super("Connect required for #{connections.size} OAuth MCP server(s) before launching")
    end
  end
end
