# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the API project-workflows endpoints, via
# the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Api::V1::Projects::WorkflowsPolicy < Web::Company::Projects::WorkflowsPolicy):
#   show?    => project_accessible?  (read)
#   update?  => project_writable?    (write)
#   destroy? => project_writable?    (write)
#     project_writable? == project_accessible? && !current_user.read_only?
#
# Inaccessible project (stranger / foreign admin) => 404: policy_context resolves
# current_project through Project.for_user(current_user).find, so the scoped
# `.find` raises RecordNotFound during authorization, before the policy predicate
# runs. The read-only viewer passes project_accessible? (200 on show) but fails
# project_writable? (403 on writes). A project has no auto-created workflow, so a
# project-scoped @workflow fixture is built here (active + scope_type "Project",
# so it is visible_for_project and in current_project.workflows.active).
class Api::V1::Projects::WorkflowsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @workflow = create(:workflow, scope: @project)
  end

  teardown { teardown_authz }

  test "show is a project read" do
    assert_project_read(transport: :api) { get api_v1_project_workflow_path(@project, @workflow) }
  end

  test "update is a project write" do
    assert_project_write(transport: :api) do
      patch api_v1_project_workflow_path(@project, @workflow),
            params: { workflow: { name: "Renamed by authz test" } }, as: :json
    end
  end

  # destroy soft-deletes, so build a throwaway workflow per role iteration to keep
  # @workflow intact. A fresh workflow has no column bindings and no active runs,
  # so soft_delete! succeeds and the allowed roles get a clean 204.
  test "destroy is a project write" do
    assert_project_write(transport: :api) do
      delete api_v1_project_workflow_path(@project, create(:workflow, scope: @project))
    end
  end
end
