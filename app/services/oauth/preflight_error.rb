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
      super("Connect required before launching: #{self.class.names(connections)}")
    end

    # The browser gets the whole `connections` list and renders it, but a
    # workflow-step launch has no browser: the relay stores only this message on
    # the admission, and that was the operator's entire account of a blocked
    # run. "1 OAuth MCP server(s)" left them to guess which one — production,
    # 2026-09-09: nine Verify steps refused over three and a half hours because
    # one project-shared grant had expired, and nothing said whose.
    def self.names(connections)
      connections.map { |c| c[:name].presence || "MCP server ##{c[:mcp_server_id]}" }.join(", ")
    end
  end
end
