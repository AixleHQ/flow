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

  test "attaching a tracker its connection no longer covers says why instead of failing" do
    @tracker.detach!
    @integration.update!(settings: @integration.settings.merge("azure_project_ids" => [ @second ]))

    patch company_project_tracker_path(@project, @tracker), params: { tracker: { status: "active" } }

    assert_redirected_to company_project_trackers_path(@project)
    assert_predicate @tracker.reload, :detached?
    follow_redirect!
    assert_inertia_props do |props|
      assert_match(/no longer covers Customer Platform\. Add it to the connection on the Integrations page/, props[:errors][:status])
    end
  end

  test "a handle another tracker has is refused with a readable reason" do
    create(:project_tracker, integration: @integration, external_scope_id: @second, handle: "ops")

    patch company_project_tracker_path(@project, @tracker), params: { tracker: { handle: "ops" } }

    assert_equal "boards", @tracker.reload.handle
    follow_redirect!
    assert_inertia_props { |props| assert_equal "Handle has already been taken", props[:errors][:handle] }
  end

  test "statuses lists the tracker's board columns for the pickers" do
    with_azure_devops_enabled
    stub_azure_devops!(integration: @integration)

    get statuses_company_project_tracker_path(@project, @tracker), as: :json

    assert_response :success
    assert_equal [ "New", "Ready for AI", "Active", "Closed" ], response.parsed_body["statuses"].pluck("name")
  end

  test "the intake shortcut gets the project's workflows and board columns" do
    create(:board_column, board: create(:board, project: @project), name: "Inbox", position: 1)
    create(:workflow, scope: @project, name: "Intake")

    get company_project_trackers_path(@project)

    assert_inertia_props do |props|
      props[:workflows].map { |w| w[:name] } == [ "Intake" ] && props[:boardColumns].map { |c| c[:name] } == [ "Inbox" ]
    end
  end
end
