# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for Web::Company::Projects::RepositoriesController,
# via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (app/policies/web/company/projects/repositories_policy.rb):
#   index?                       => project_accessible?                     (read)
#   create? / update? / destroy? => project_writable? && current_user.admin? (write + admin role)
#
# The read (index) follows the standard project-read matrix. The writes are NOT
# the standard project-write preset: they additionally require the company ADMIN
# *role* (current_user.admin?), so only @admin is allowed. The project owner and
# the employee collaborator have project_writable? access but lack the admin
# role, so they are DENIED; the read-only viewer is denied too. A same-company
# stranger and a foreign-company admin are scoped out by the controller's
# Project.for_user(current_user).find -> RecordNotFound -> 404 (before the policy
# runs, when policy_context resolves current_project).
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

  test "create requires the company admin role (project write + admin?)" do
    assert_role_matrix(admin_write_expectations, transport: :web) do
      post company_project_repositories_path(@project), params: {
        repository: {
          full_name: "acme/authz-service",
          clone_url: "https://github.com/acme/authz-service.git",
          source_branch: "main",
          integration_id: @integration.id
        }
      }
    end
  end

  test "update requires the company admin role (project write + admin?)" do
    assert_role_matrix(admin_write_expectations, transport: :web) do
      patch company_project_repository_path(@project, @repository),
            params: { repository: { description: "Updated by matrix" } }
    end
  end

  # destroy mutates, so build a throwaway project-scoped repository per iteration.
  test "destroy requires the company admin role (project write + admin?)" do
    assert_role_matrix(admin_write_expectations, transport: :web) do
      delete company_project_repository_path(@project, create(:repository, scope: @project, integration: @integration))
    end
  end

  private

  # create/update/destroy gate on project_writable? AND current_user.admin?, so
  # only the company admin passes; the owner and employee/viewer collaborators
  # are denied, and non-members (stranger/foreign admin) are scoped out to 404.
  def admin_write_expectations
    {
      admin: :allowed_write,
      owner: :denied, collaborator: :denied, viewer: :denied,
      stranger: :not_found, foreign_admin: :not_found
    }
  end
end
