# frozen_string_literal: true

require "test_helper"

# Connecting YouTrack through the real endpoints: a permanent token checked,
# then connected to the projects picked, and the Webhook Triggers settings a
# project admin copies into YouTrack. The REST API behind it is FakeYoutrack::Api.
class Web::Company::Projects::YoutrackIntegrationsTest < ActionDispatch::IntegrationTest
  APP = FakeYoutrack::Api::APP
  OPS = FakeYoutrack::Api::OPS

  setup do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    @youtrack = stub_youtrack!
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "a token is checked, then connected to the projects picked" do
    post youtrack_inspect_company_project_integrations_path(@project),
         params: { base_url: "https://Acme.youtrack.cloud/api/", permanent_token: "perm:x" }, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal [ "https://acme.youtrack.cloud", "aixle", %w[APP OPS] ],
                 [ body["base_url"], body.dig("identity", "login"), body["projects"].pluck("key") ]

    post company_project_integrations_path(@project),
         params: { provider: "youtrack", base_url: body["base_url"], permanent_token: "perm:x", project_ids: [ APP ], dedicated_identity: "true" }

    assert_redirected_to company_project_integrations_path(@project)
    integration = Integration.find_by!(project: @project, provider: "youtrack")
    assert_equal [ "active", [ APP ], true, [ APP ] ],
                 [ integration.status.to_s, integration.project_trackers.pluck(:external_scope_id),
                   integration.settings["dedicated_identity"], integration.tracker_subscriptions.pluck(:external_scope_id) ]
    card = IntegrationResource.new(integration.reload).to_h.stringify_keys
    assert_equal [ "https://acme.youtrack.cloud", "aixle", [ "APP" ] ],
                 card.values_at("youtrackBaseUrl", "youtrackIdentity", "youtrackWebhooksPending")
    assert_not card.to_json.include?(integration.tracker_subscriptions.sole.secret)
  end

  test "a token YouTrack refuses is reported against the dialog, and nothing is saved" do
    @youtrack.fail_next(:me, Trackers::Error.new("YouTrack rejected the permanent token", code: "not_authorized"))

    post youtrack_inspect_company_project_integrations_path(@project),
         params: { base_url: "https://acme.youtrack.cloud", permanent_token: "bad" }, as: :json

    assert_response :unprocessable_content
    assert_equal "not_authorized", response.parsed_body["error"]
    assert_equal 0, Integration.where(project: @project).count
  end

  test "an http URL is refused before any request" do
    post youtrack_inspect_company_project_integrations_path(@project),
         params: { base_url: "http://acme.youtrack.cloud", permanent_token: "perm:x" }, as: :json

    assert_response :unprocessable_content
    assert_match(/https/, response.parsed_body["message"])
    assert_not @youtrack.called?(:me)
  end

  test "connecting the same instance again replaces the token in place and says when the account changed" do
    integration = create(:integration, :youtrack, :active, project: @project, company: @company, connected_by: @user)
    Trackers::Provisioning.ensure_for!(integration)
    @youtrack.me = FakeYoutrack::Api::USERS[1].dup

    post company_project_integrations_path(@project),
         params: { provider: "youtrack", base_url: FakeYoutrack::Api::BASE_URL, permanent_token: "perm:new", project_ids: [ APP, OPS ] }

    assert_equal [ integration.id ], Integration.where(project: @project, provider: "youtrack").pluck(:id)
    assert_equal [ "perm:new", "jdoe" ], [ integration.reload.credentials_data["permanent_token"], integration.settings["identity_login"] ]
    assert_match(/now acts as @jdoe, not @aixle/, flash[:alert])
  end

  test "the webhook settings list each project's URL, header and token, and an existing token can be kept" do
    integration = create(:integration, :youtrack, :active, project: @project, company: @company, connected_by: @user)

    get youtrack_webhook_company_project_integration_path(@project, integration), as: :json

    projects = response.parsed_body["projects"]
    assert_equal [ %w[APP X-YouTrack-Token], %w[OPS X-YouTrack-Token] ], projects.map { |p| p.values_at("key", "header") }
    assert projects.all? { |p| p["url"].include?("/webhooks/trackers/") && p["token"].length == 64 }

    existing = "e" * 40
    patch youtrack_webhook_token_company_project_integration_path(@project, integration),
          params: { scope_id: APP, token: existing, header: "X-Hook-Token" }, as: :json

    assert_response :success
    assert_equal [ existing, "X-Hook-Token" ], response.parsed_body.values_at("token", "header")
    assert_equal existing, integration.tracker_subscriptions.find_by!(external_scope_id: APP).secret
  end

  test "dropping a project detaches its tracker and disables its webhook" do
    integration = create(:integration, :youtrack, :active, project: @project, company: @company, connected_by: @user)
    Trackers::Provisioning.ensure_for!(integration)
    Trackers::Youtrack::Subscriptions.new(integration).ensure!

    patch company_project_integration_path(@project, integration), params: { project_ids: [ APP ] }

    assert_equal "detached", integration.project_trackers.find_by!(external_scope_id: OPS).status
    assert_equal "disabled", integration.tracker_subscriptions.find_by!(external_scope_id: OPS).status
  end
end
