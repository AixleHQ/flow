# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the project-scoped Workflows controller,
# via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Web::Company::Projects::WorkflowsPolicy):
#   reads  (index/builder)                         => project_accessible?
#   writes (create/update/destroy/publish/         => project_writable?
#           unpublish/duplicate)
# Inaccessible project (stranger / foreign admin) => 404 (current_project's scoped
# `.find` raises RecordNotFound before the policy). A project has no auto-created
# workflow, so the fixture is built here (scope: @project => visible_for_project).
#
# NOTE: `unpublish` layers an extra CONTROLLER guard on top of the policy
# ("only the publisher or an admin can unpublish"). That is business logic, not
# authorization, so the test makes each acting role the publisher (published_by:
# user_for(role)) — the guard then passes for every policy-allowed role and the
# assertion reflects the pure authorization outcome (302 redirect, no alert).
#
# The policy also declares show?, but this controller exposes no route for it
# (the workflow's own screen is `builder`), so there is nothing to exercise.
class Web::Company::Projects::WorkflowsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @workflow = create(:workflow, scope: @project)
  end

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read { get company_project_workflows_path(@project) }
  end

  test "builder is a project read" do
    assert_project_read { get builder_company_project_workflow_path(@project, @workflow) }
  end

  test "create is a project write" do
    assert_project_write do
      post company_project_workflows_path(@project),
           params: { workflow: { name: "Authz WF #{SecureRandom.hex(4)}", description: "x" } }
    end
  end

  # A rename per role iteration would collide on the name-uniqueness validation,
  # which fails the write without ever reaching the policy — so each role edits
  # its own throwaway workflow.
  test "update is a project write" do
    assert_project_write do
      patch company_project_workflow_path(@project, create(:workflow, scope: @project)),
            params: { workflow: { description: "authz edit" } }
    end
  end

  # destroy mutates, so build a throwaway workflow per role iteration.
  test "destroy is a project write" do
    assert_project_write do
      delete company_project_workflow_path(@project, create(:workflow, scope: @project))
    end
  end

  test "publish is a project write" do
    assert_project_write { post publish_company_project_workflow_path(@project, @workflow) }
  end

  # unpublish's policy gate is project_writable?; the controller's publisher/admin
  # guard is separate business logic. Make each acting role the publisher so that
  # guard passes and only the authorization outcome remains under test.
  test "unpublish is a project write" do
    assert_project_write do |role|
      workflow = create(:workflow, scope: @project, published_at: Time.current, published_by: user_for(role))
      post unpublish_company_project_workflow_path(@project, workflow)
    end
  end

  test "duplicate is a project write" do
    assert_project_write { post duplicate_company_project_workflow_path(@project, @workflow) }
  end
end
