# frozen_string_literal: true

module Web
  module Company
    module Projects
      class MCPServersPolicy < Web::Company::ApplicationPolicy
        def index? = project_accessible?
        def create? = project_writable?
        def update? = project_writable?
        def destroy? = project_writable?

        # Both member actions change what an installed server serves — the
        # connector version it runs, or the tool baseline it is trusted at — so
        # they are writes, same as #update.
        def update_connector? = project_writable?
        def accept_tool_drift? = project_writable?
      end
    end
  end
end
