# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the project-scoped MCPServers controller,
# via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Web::Company::Projects::MCPServersPolicy) — the controller exposes only
# these four actions (no show/new/edit):
#   index?                       => project_accessible?  (read)
#   create? / update? / destroy? => project_writable?    (write)
#
# project_accessible? = project.accessible_by?(user); project_writable? = accessible
# AND !user.read_only? (the viewer persona is read_only, so it is denied writes).
# Stranger / foreign-company user: the project is outside Project.for_user, so
# current_project's `.find` raises RecordNotFound before the policy => 404 for
# every action.
#
# MCPServer#name is unique within its scope, so the create body generates a fresh
# name per role iteration (the harness runs all allowed roles in one transaction).
class Web::Company::Projects::MCPServersAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @server = create(:mcp_server, scope: @project, kind: :custom)
  end

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read { get company_project_mcp_servers_path(@project) }
  end

  test "create is a project write" do
    assert_project_write do
      post company_project_mcp_servers_path(@project), params: {
        mcp_server: { name: "authz-mcp-#{SecureRandom.hex(4)}", display_name: "Authz MCP",
                      url: "https://mcp.test/v1", transport: "sse" }
      }
    end
  end

  test "update is a project write" do
    assert_project_write do
      patch company_project_mcp_server_path(@project, @server), params: {
        mcp_server: { display_name: "Renamed by authz" }
      }
    end
  end

  # destroy mutates, so build a throwaway server per role iteration.
  test "destroy is a project write" do
    assert_project_write do
      delete company_project_mcp_server_path(@project, create(:mcp_server, scope: @project, kind: :custom))
    end
  end
end
