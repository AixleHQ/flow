# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the project-scoped Tools controller, via
# the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Web::Company::Projects::ToolsPolicy):
#   index?                        => project_accessible?  (read)
#   create? / update? / destroy?  => project_writable?    (write — owner/admin/
#                                    collaborator allowed, viewer denied,
#                                    non-members scoped out to 404)
#
# Writes carry a valid db-source custom-tool body (name matches the model's
# lowercase format, display_name + docker_image are required for db_source);
# the tool is scoped to the project automatically via current_project.tools.
class Web::Company::Projects::ToolsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @tool = create(:tool, scope: @project)
  end

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read { get company_project_tools_path(@project) }
  end

  test "create is a project write" do
    assert_project_write do
      post company_project_tools_path(@project),
           params: { tool: { name: "authz_tool_#{SecureRandom.hex(4)}",
                             display_name: "Authz Tool", docker_image: "alpine:latest" } }
    end
  end

  test "update is a project write" do
    assert_project_write do
      patch company_project_tool_path(@project, @tool), params: { tool: { display_name: "Renamed" } }
    end
  end

  # destroy soft-deletes, so build a throwaway project-scoped tool per role.
  test "destroy is a project write" do
    assert_project_write do
      delete company_project_tool_path(@project, create(:tool, scope: @project))
    end
  end
end
