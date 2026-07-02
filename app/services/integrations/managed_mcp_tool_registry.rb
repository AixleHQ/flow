# frozen_string_literal: true

module Integrations
  # DEPRECATED shim: provider → managed tool names now live on the tool
  # definitions themselves (`managed_mcp_provider :coder` in the tool DSL,
  # queried via Tools::Registry.managed_tool_names). Kept for one release for
  # any out-of-tree callers; delete in Stage 4 of the registry migration.
  class ManagedMCPToolRegistry
    class << self
      def tool_names_for(provider)
        Tools::Registry.managed_tool_names(provider)
      end

      def known?(tool_name)
        Tools::Registry.fetch(tool_name)&.managed_mcp_provider.present?
      end
    end
  end
end
