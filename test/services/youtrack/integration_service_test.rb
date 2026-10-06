# frozen_string_literal: true

require "test_helper"

class Youtrack::IntegrationServiceTest < ActiveSupport::TestCase
  APP = FakeYoutrack::Api::APP

  setup do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    @youtrack = stub_youtrack!
    company = create(:company)
    @user = create(:user, company: company)
    @project = create(:project, company: company, owner: @user)
    @service = Youtrack::IntegrationService.new(company: @project.company, connected_by: @user, project: @project)
  end

  test "connecting keeps each project's state and assignee fields and makes it a tracker with a webhook" do
    integration = @service.connect(base_url: "https://acme.youtrack.cloud/", token: " perm:x ", project_ids: [ APP ])

    assert_equal [ { "id" => APP, "key" => "APP", "name" => "Application", "status_field" => "State", "assignee_field" => "Assignee" } ],
                 integration.settings["youtrack_projects"]
    assert_equal [ "perm:x", "https://acme.youtrack.cloud", false ],
                 [ integration.credentials_data["permanent_token"], integration.settings["base_url"], integration.settings["dedicated_identity"] ]
    assert_equal [ [ "application", true ] ], integration.project_trackers.pluck(:handle, :primary)
    assert_equal [ APP ], integration.tracker_subscriptions.pluck(:external_scope_id)
    assert_nil @service.previous_login
  end

  test "a project the token cannot see, or none at all, is refused" do
    assert_raises(Youtrack::IntegrationService::ConfigurationError) { @service.connect(base_url: "https://acme.youtrack.cloud", token: "t", project_ids: [ "0-9" ]) }
    assert_raises(Youtrack::IntegrationService::ConfigurationError) { @service.connect(base_url: "https://acme.youtrack.cloud", token: "t", project_ids: []) }
    assert_raises(Youtrack::IntegrationService::ConfigurationError) { @service.inspect_token(base_url: "acme", token: "t") }
  end

  test "a test refreshes the projects and warns about one the token lost; a refused token marks the connection" do
    integration = create(:integration, :youtrack, :active, project: @project, company: @project.company,
                         youtrack_projects: [ { "id" => APP, "key" => "OLD", "name" => "Old name" }, { "id" => "0-9", "key" => "GONE", "name" => "Gone" } ])

    result = @service.test(integration)
    assert_equal [ :active, "This connection can no longer see GONE" ], result.values_at(:status, :message)
    assert_equal "APP", integration.reload.settings["youtrack_projects"].first["key"]

    @youtrack.fail_next(:me, Trackers::Error.new("YouTrack rejected the permanent token", code: "not_authorized"))
    assert_equal :error, @service.test(integration)[:status]
    assert_equal "error", integration.reload.status

    @youtrack.fail_next(:me, Trackers::Error.new("YouTrack could not be reached", code: "timeout"))
    integration.update!(status: :active)
    @service.test(integration)
    assert_equal "active", integration.reload.status
  end
end
