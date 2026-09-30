# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::TrackersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    @integration = create(:integration, :azure_devops, :active, company: @company, project: @project, connected_by: @user)
    first = @integration.azure_project_ids.first
    @second = SecureRandom.uuid
    @integration.azure_devops_installation.update!(allowed_project_ids: [ first, @second ])
    @integration.update!(settings: @integration.settings.merge(
      "azure_project_ids" => [ first, @second ], "azure_project_names" => { first => "Customer Platform", @second => "Ops" }
    ))
    @tracker = create(:project_tracker, :primary, integration: @integration, handle: "boards")
    sign_in_as(@user)
  end

  test "index lists the trackers and only the external projects not mapped yet" do
    get company_project_trackers_path(@project)

    assert_inertia_page "Projects/Trackers/TrackersPage"
    assert_inertia_props do |props|
      scopes = props[:availableScopes].sole[:scopes]
      props[:trackers].map { |t| t[:handle] } == [ "boards" ] &&
        scopes.map { |s| [ s[:id], s[:name] ] } == [ [ @second, "Ops" ] ]
    end
  end

  test "adding a tracker suggests a handle and can take over as primary" do
    assert_difference("ProjectTracker.count", 1) do
      post company_project_trackers_path(@project),
           params: { tracker: { integrationId: @integration.id, externalScopeId: @second, primary: true, access: "read_only" } }
    end

    added = ProjectTracker.find_by!(external_scope_id: @second)
    assert_equal [ "ops", "read_only", true ], [ added.handle, added.access, added.primary ]
    refute @tracker.reload.primary
    assert_redirected_to company_project_trackers_path(@project)
  end

  test "a project the connection does not cover is refused" do
    assert_no_difference("ProjectTracker.count") do
      post company_project_trackers_path(@project),
           params: { tracker: { integration_id: @integration.id, external_scope_id: SecureRandom.uuid } }
    end

    assert_redirected_to company_project_trackers_path(@project)
  end

  test "update changes access and handle, and removing detaches rather than deletes" do
    patch company_project_tracker_path(@project, @tracker), params: { tracker: { access: "read_only", handle: "azure" } }
    assert_equal %w[read_only azure], [ @tracker.reload.access, @tracker.handle ]

    delete company_project_tracker_path(@project, @tracker)
    assert_equal [ "detached", false ], [ @tracker.reload.status, @tracker.primary ]

    patch company_project_tracker_path(@project, @tracker), params: { tracker: { status: "active" } }
    assert @tracker.reload.active?
  end
end
