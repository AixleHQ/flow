# frozen_string_literal: true

module Web
  module Company
    module Projects
      # Browsing the connector catalog and installing from it are the same
      # permissions as managing MCP servers by hand — installing a connector
      # simply produces an MCPServer row (see MCP::ConnectorAttributes).
      #
      # This class exists because Pundit resolves a policy per controller
      # namespace, not because the catalog introduces a permission concept.
      # Keep it in lockstep with MCPServersPolicy: if one gains a rule, so does
      # the other, or the catalog becomes a way around the manual form's checks.
      class ConnectorsPolicy < Web::Company::ApplicationPolicy
        # No index?: the catalog is browsed from the MCP servers page, which
        # MCPServersPolicy already gates. Only installing happens here.
        def create? = project_writable?
      end
    end
  end
end
