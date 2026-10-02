# frozen_string_literal: true

require "test_helper"

# Request-level authorization for the project's Triggers page and its list
# (docs/testing.md §2). Both read; writes go through the workflow triggers API,
# whose matrix is test/integration/api/v1/projects/workflows/triggers_authorization_test.rb.
class Web::Company::Projects::TriggersAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    create(:trigger_binding, project: @project, workflow: create(:workflow, scope: @project), created_by: @owner)
  end

  teardown { teardown_authz }

  test "the page is a project read" do
    assert_project_read { get company_project_triggers_path(@project) }
  end

  test "the list is a project read" do
    assert_project_read(transport: :api) { get api_v1_project_triggers_path(@project) }
  end
end
