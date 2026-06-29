# frozen_string_literal: true

module Integrations
  # ManagedMCPToolRegistry — maps an integration `provider` to the list of
  # internal tools its managed MCP server exposes to agents.
  #
  # The MCP dispatcher (config/initializers/action_mcp_dynamic_tools.rb) is
  # provider-agnostic: it asks the registry which tools a given managed
  # server should surface, instead of hard-coding provider-specific names.
  # Each provider registers itself once (typically in an initializer or
  # alongside its service code).
  class ManagedMCPToolRegistry
    @registry = {}

    class << self
      def register(provider, tool_names:)
        @registry[provider.to_s] = tool_names.map(&:to_s).freeze
      end

      def tool_names_for(provider)
        @registry[provider.to_s] || []
      end

      def known?(tool_name)
        @registry.values.any? { |names| names.include?(tool_name.to_s) }
      end

      def clear!
        @registry = {}
      end
    end

    # Built-in registrations. Add new providers here (or in the provider's
    # own initializer) when they expose managed MCP tools.
    register("coder", tool_names: %w[
      coder_allocate_machine
      coder_ssh_exec
      coder_release_machine
    ])
  end
end
