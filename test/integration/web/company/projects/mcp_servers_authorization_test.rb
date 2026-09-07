# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the project-scoped MCPServers controller,
# via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Web::Company::Projects::MCPServersPolicy) — the controller exposes no
# show/new/edit; everything else is here:
#   index?                          => project_accessible?  (read)
#   create? / update? / destroy?    => project_writable?    (write)
#   update_connector?               => project_writable?    (write, member)
#   accept_tool_drift?              => project_writable?    (write, member)
#
# accept_tool_drift is covered by the policy unit test instead: accepting a
# baseline re-probes the live MCP server, which the WebMock fence forbids, so
# there is no body an allowed role can send here without inventing a network.
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
        mcp_server: { name: "authz-mcp-#{SecureRandom.hex(4)}",
                      url: "https://mcp.test/v1", transport: "sse" }
      }
    end
  end

  test "update is a project write" do
    assert_project_write do
      patch company_project_mcp_server_path(@project, @server), params: {
        mcp_server: { description: "Renamed by authz" }
      }
    end
  end

  # destroy mutates, so build a throwaway server per role iteration.
  test "destroy is a project write" do
    assert_project_write do
      delete company_project_mcp_server_path(@project, create(:mcp_server, scope: @project, kind: :custom))
    end
  end

  # This action reached production with no `update_connector?` on the policy, so
  # the dynamic authorize raised NoMethodError and every role got a 500 —
  # including the viewer this asserts is turned away.
  #
  # `allowed:` pins the redirect only: a hand-written server carries no
  # connector_name, so the allowed roles bounce off "no longer in the catalog"
  # with an alert of their own, and the harness's no-alert check for a clean
  # write would read that as a denial.
  test "update_connector is a project write" do
    assert_project_write(allowed: :redirect) do
      post update_connector_company_project_mcp_server_path(@project, @server)
    end
  end
end
