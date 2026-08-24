# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for Web::Company::Projects::RepositoriesController,
# via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (app/policies/web/company/projects/repositories_policy.rb):
#   index?                       => project_accessible?  (read)
#   create? / update? / destroy? => project_writable?    (write)
#
# The standard project matrices apply: attaching a repository is the same
# authority as adding an agent or an MCP server. The read-only viewer is denied
# the writes; a same-company stranger and a foreign-company admin are scoped out
# by the controller's Project.for_user(current_user).find -> RecordNotFound ->
# 404 (before the policy runs, when policy_context resolves current_project).
class Web::Company::Projects::RepositoriesAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @integration = create(:integration, :github, company: @company, connected_by: @owner)
    @repository = create(:repository, scope: @project, integration: @integration)
  end

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read { get company_project_repositories_path(@project) }
  end

  test "create is a project write" do
    assert_project_write do |role|
      post company_project_repositories_path(@project), params: {
        repository: {
          full_name: "acme/authz-service-#{role}",
          clone_url: "https://github.com/acme/authz-service.git",
          source_branch: "main",
          integration_id: @integration.id
        }
      }
    end
  end

  test "update is a project write" do
    assert_project_write do
      patch company_project_repository_path(@project, @repository),
            params: { repository: { description: "Updated by matrix" } }
    end
  end

  # destroy mutates, so build a throwaway project-scoped repository per iteration.
  test "destroy is a project write" do
    assert_project_write do
      delete company_project_repository_path(@project, create(:repository, scope: @project, integration: @integration))
    end
  end
end
