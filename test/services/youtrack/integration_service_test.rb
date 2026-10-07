# frozen_string_literal: true

require "test_helper"

class Youtrack::IntegrationServiceTest < ActiveSupport::TestCase
  APP = FakeYoutrack::Api::APP
  OPS = FakeYoutrack::Api::OPS

  setup do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    @youtrack = stub_youtrack!
    company = create(:company)
    @user = create(:user, company: company)
    @project = create(:project, company: company, owner: @user)
    @service = Youtrack::IntegrationService.new(company: @project.company, connected_by: @user, project: @project)
  end

  def connect(**overrides)
    @service.connect_app(base_url: "https://acme.youtrack.cloud/", token: " perm:x ", login: "aixle", project_ids: [ APP ],
                         app_version: "1.0.0", **overrides)
  end

  test "the app's token becomes a connection whose projects are trackers, each with an app subscription" do
    integration = connect

    assert_equal [ { "id" => APP, "key" => "APP", "name" => "Application", "status_field" => "State", "assignee_field" => "Assignee" } ],
                 integration.settings["youtrack_projects"]
    assert_equal [ "perm:x", "https://acme.youtrack.cloud", "app", "1.0.0", "aixle" ],
                 [ integration.credentials_data["permanent_token"], *integration.settings.values_at("base_url", "auth_mode", "app_version"),
                   integration.settings.dig("tracker_identity", "login") ]
    assert_equal [ [ "application", true ] ], integration.project_trackers.pluck(:handle, :primary)
    assert_equal [ [ APP, "app" ] ], integration.tracker_subscriptions.pluck(:external_scope_id, :strategy)
  end

  test "connecting the same instance again replaces the token in place and follows the projects chosen" do
    integration = connect(project_ids: [ APP, OPS ])
    secrets = integration.tracker_subscriptions.order(:external_scope_id).map(&:secret)

    again = connect(token: "perm:new", project_ids: [ APP ])

    assert_equal integration.id, again.id
    assert_equal "perm:new", again.reload.credentials_data["permanent_token"]
    assert_equal({ APP => "active", OPS => "detached" }, again.project_trackers.pluck(:external_scope_id, :status).to_h)
    assert_equal secrets.first, again.tracker_subscriptions.find_by!(external_scope_id: APP).secret
  end

  test "a token that is not the service user's, a project it cannot see, or a plain-http instance is refused" do
    assert_raises(Youtrack::IntegrationService::ConfigurationError) { connect(login: "someone-else") }
    assert_raises(Youtrack::IntegrationService::ConfigurationError) { connect(project_ids: [ "0-9" ]) }
    assert_raises(Youtrack::IntegrationService::ConfigurationError) { connect(project_ids: []) }
    assert_raises(Youtrack::IntegrationService::ConfigurationError) { connect(base_url: "http://acme.youtrack.cloud") }
    assert_equal 0, Integration.where(provider: "youtrack").count
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
