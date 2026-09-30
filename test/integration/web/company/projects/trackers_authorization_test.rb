# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for Web::Company::Projects::TrackersController.
# Adding a tracker from a connection the project already sees is a project write,
# like attaching a repository (app/policies/web/company/projects/trackers_policy.rb).
class Web::Company::Projects::TrackersAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @integration = create(:integration, :azure_devops, :active, company: @company, project: @project, connected_by: @owner)
    @tracker = create(:project_tracker, integration: @integration)
  end

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read { get company_project_trackers_path(@project) }
  end

  test "create is a project write" do
    assert_project_write do
      post company_project_trackers_path(@project),
           params: { tracker: { integration_id: @integration.id, external_scope_id: @tracker.external_scope_id } }
    end
  end

  test "update is a project write" do
    assert_project_write do
      patch company_project_tracker_path(@project, @tracker), params: { tracker: { access: "read_only" } }
    end
  end

  test "destroy is a project write" do
    assert_project_write { delete company_project_tracker_path(@project, @tracker) }
  end
end
