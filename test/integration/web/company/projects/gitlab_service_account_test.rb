# frozen_string_literal: true

require "test_helper"

# Connecting GitLab through the real endpoints (docs/design/gitlab-tracker.md
# §4–5): the OAuth app's round trip, the group that becomes the service
# account's, and the projects whose boards become trackers. GitLab's token
# endpoint and REST calls are WebMock-stubbed; the tracker API behind the
# provider is FakeGitlab::TrackerApi.
class Web::Company::Projects::GitlabServiceAccountTest < ActionDispatch::IntegrationTest
  API = "https://gitlab.com/api/v4"

  setup do
    Settings.gitlab.stubs(:oauth_client_id).returns("gl-app")
    Settings.gitlab.stubs(:oauth_client_secret).returns("gl-secret")
    Gitlab::AppConfig.stubs(:webhooks_enabled?).returns(true)
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    @gitlab = stub_gitlab_tracker!
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  def json(body, status: 200) = { status: status, body: body.to_json, headers: { "Content-Type" => "application/json" } }

  test "the page says whether the OAuth app is available" do
    get company_project_integrations_path(@project)

    assert_inertia_props { |props| assert props["gitlab"]["oauthEnabled"] }
  end

  test "signing in, picking the group and picking a board leave a bot connection with a tracker and its hook" do
    get gitlab_oauth_start_company_project_integrations_path(@project)
    state = Rack::Utils.parse_query(URI.parse(response.location).query)["state"]
    stub_request(:post, "https://gitlab.com/oauth/token").to_return(json({ access_token: "person-token", expires_in: 7200 }))
    stub_request(:get, "#{API}/user").to_return(json({ id: 7, username: "owner" }))
    stub_request(:get, "#{API}/groups").with(query: hash_including("min_access_level" => "50"))
      .to_return(json([ { id: 31, full_path: "acme", name: "Acme" } ]))

    get gitlab_oauth_callback_path, params: { code: "c0de", state: state }

    pending = Integration.find_by!(project: @project, provider: "gitlab")
    assert_redirected_to company_project_integrations_path(@project, gitlab_setup: pending.id)

    stub_request(:get, "#{API}/groups/31/service_accounts").with(query: hash_including({})).to_return(json([]))
    stub_request(:post, "#{API}/groups/31/service_accounts").to_return(json({ id: 900, username: "aixle-flow-ab12" }, status: 201))
    stub_request(:post, "#{API}/groups/31/members").to_return(json({ message: "Member already exists" }, status: 409))
    stub_request(:post, "#{API}/groups/31/service_accounts/900/personal_access_tokens")
      .to_return(json({ id: 55, token: "glpat-bot", expires_at: nil }, status: 201))

    patch company_project_integration_path(@project, pending), params: { gitlab_group_id: "31" }

    assert_equal [ "active", "aixle-flow-ab12" ], [ pending.reload.status.to_s, pending.settings["gitlab_username"] ]
    stub_request(:get, "#{API}/projects").with(query: hash_including("membership" => "true"))
      .with(headers: { "Authorization" => "Bearer glpat-bot" })
      .to_return(json([ { id: 501, path_with_namespace: "acme/app", name_with_namespace: "Acme / App" } ]))

    get gitlab_projects_company_project_integration_path(@project, pending), as: :json
    assert_equal [ "acme/app" ], response.parsed_body["projects"].pluck("path")
    get gitlab_boards_company_project_integration_path(@project, pending, gitlab_project_id: "501"), as: :json
    assert_response :success, response.body
    assert_equal [ "Development" ], response.parsed_body["boards"].pluck("name")

    patch company_project_integration_path(@project, pending), params: { gitlab_trackers: [ { project_id: "501", board_id: "71" } ] }

    tracker = ProjectTracker.find_by!(project: @project, integration: pending)
    assert_equal [ "501", "acme/app", true ], [ tracker.external_scope_id, tracker.external_scope_key, tracker.primary ]
    assert_equal [ "501" ], @gitlab.hooks.values.pluck(:project_id)
    assert_equal "active", pending.tracker_subscriptions.sole.status.to_s
  end

  test "a link already used, or someone else's, connects nothing" do
    get gitlab_oauth_start_company_project_integrations_path(@project)
    state = Rack::Utils.parse_query(URI.parse(response.location).query)["state"]
    Oauth::State.consume(Oauth::State.decode(state)["nonce"])

    get gitlab_oauth_callback_path, params: { code: "c0de", state: state }

    assert_redirected_to company_project_integrations_path(@project)
    assert_equal 0, Integration.where(provider: "gitlab").count
  end

  test "disconnecting a service-account connection revokes its token; the account stays for the group's Owner" do
    integration = create(:integration, :gitlab, :active, company: @company, project: @project)
    integration.credentials_data = { "personal_access_token" => "glpat-bot" }
    integration.update!(settings: { "auth_mode" => "service_account", "gitlab_user_id" => "900" })
    revoked = stub_request(:delete, "#{API}/personal_access_tokens/self").with(headers: { "Authorization" => "Bearer glpat-bot" })
                .to_return(status: 204)

    delete company_project_integration_path(@project, integration)

    assert_redirected_to company_project_integrations_path(@project)
    assert_requested revoked
    assert_not Integration.exists?(integration.id)
  end

  test "disconnecting a pasted token's connection leaves the token alone" do
    integration = create(:integration, :gitlab, :active, company: @company, project: @project)

    delete company_project_integration_path(@project, integration)

    assert_not Integration.exists?(integration.id)
    assert_not_requested :delete, "#{API}/personal_access_tokens/self"
  end
end
