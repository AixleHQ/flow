# frozen_string_literal: true

module InternalTools
  module Concerns
    # CoderResolver — pull the Coder integration this tool call is routed to.
    #
    # Strategy: the tool call is routed through a managed MCP server bound
    # to exactly one Coder integration. `mcp_server.integration` is the FK
    # back. This is the only point where multi-integration routing matters,
    # and it ends up being a one-liner because the managed MCP server is
    # the disambiguator.
    module CoderResolver
      class NotConfiguredError < StandardError; end

      def coder_integration
        @coder_integration ||= resolve_coder_integration
      end

      def require_coder!
        return if coder_integration

        raise NotConfiguredError,
              "This tool was called outside the context of a managed Coder MCP server. " \
              "Bind the step to the Coder integration's MCP server first."
      end

      private

      def resolve_coder_integration
        server = mcp_server
        return nil unless server&.managed?
        return nil unless server.integration&.provider.to_s == "coder"
        return nil unless server.integration.active?

        server.integration
      end
    end
  end
end
