# frozen_string_literal: true

require "test_helper"

# Both ways of connecting Jira through the real endpoints: a service account
# pasted into the dialog, and Aixle's Atlassian OAuth app via its callback.
# Atlassian's token and tenant endpoints are WebMock-stubbed (Jira::Oauth stays
# real); the REST API behind them is FakeJira::Api.
class Web::Company::Projects::JiraIntegrationsTest < ActionDispatch::IntegrationTest
  setup do
    with_jira_oauth_app
    @cache = ActiveSupport::Cache::MemoryStore.new
    Rails.stubs(:cache).returns(@cache)
    @jira = stub_jira!
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  def stub_service_account
    stub_request(:get, "https://acme.atlassian.net/_edge/tenant_info").to_return(status: 200, body: { cloudId: "cloud-acme" }.to_json)
    stub_request(:post, "#{JIRA_AUTH}/oauth/token").with(body: hash_including("grant_type" => "client_credentials"))
      .to_return(status: 200, body: { access_token: "sa-at", expires_in: 3600 }.to_json)
  end

  test "the page says whether the OAuth app is available" do
    get company_project_integrations_path(@project)

    assert_inertia_props { |props| assert props["jira"]["oauthEnabled"] }
  end

  test "a service account is checked, then connected to the projects picked" do
    stub_service_account

    post jira_inspect_company_project_integrations_path(@project),
         params: { site_url: "acme.atlassian.net", client_id: "sa", client_secret: "secret" }, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal [ "cloud-acme", "Aixle Bot", %w[ENG OPS] ],
                 [ body.dig("site", "id"), body.dig("identity", "name"), body["projects"].pluck("key") ]

    post company_project_integrations_path(@project),
         params: { provider: "jira", site_url: "acme.atlassian.net", client_id: "sa", client_secret: "secret", project_ids: [ "10001" ] }

    assert_redirected_to company_project_integrations_path(@project)
    integration = Integration.find_by!(project: @project, provider: "jira")
    assert_equal [ "active", [ "10001" ] ], [ integration.status, integration.project_trackers.pluck(:external_scope_id) ]
  end

  test "a credential Atlassian refuses is reported against the dialog, and nothing is saved" do
    stub_request(:get, "https://acme.atlassian.net/_edge/tenant_info").to_return(status: 200, body: { cloudId: "cloud-acme" }.to_json)
    stub_request(:post, "#{JIRA_AUTH}/oauth/token").to_return(status: 401, body: { error: "access_denied" }.to_json)

    post jira_inspect_company_project_integrations_path(@project),
         params: { site_url: "acme.atlassian.net", client_id: "sa", client_secret: "wrong" }, as: :json

    assert_response :unprocessable_content
    assert_equal "not_authorized", response.parsed_body["error"]
    assert_equal 0, Integration.where(project: @project).count
  end

  test "the admin webhook's URL and secret are there for the people who manage integrations" do
    integration = create(:integration, :jira, :active, project: @project, company: @company)

    get jira_webhook_company_project_integration_path(@project, integration), as: :json

    assert_response :success
    subscription = integration.tracker_subscriptions.sole
    assert_equal [ "https://flow.example.com/webhooks/trackers/#{subscription.endpoint_token}", subscription.secret, "project IN (ENG, OPS)" ],
                 response.parsed_body.values_at("url", "secret", "jql")
  end

  test "the OAuth app round trip leaves a pending connection that the project picker finishes" do
    get jira_oauth_start_company_project_integrations_path(@project)
    authorize = URI.parse(response.location)
    assert_equal "auth.atlassian.com", authorize.host
    state = Rack::Utils.parse_query(authorize.query)["state"]
    stub_request(:post, "#{JIRA_AUTH}/oauth/token").to_return(status: 200, body: { access_token: "at", refresh_token: "rt", expires_in: 3600 }.to_json)
    stub_request(:get, "#{JIRA_API}/oauth/token/accessible-resources")
      .to_return(status: 200, body: [ { id: "cloud-acme", name: "acme", url: "https://acme.atlassian.net", scopes: [ "read:jira-work" ] } ].to_json)

    get jira_oauth_callback_path, params: { code: "c", state: state }

    integration = Integration.find_by!(project: @project, provider: "jira")
    assert_redirected_to company_project_integrations_path(@project, jira_setup: integration.id)
    assert_equal "inactive", integration.status

    get jira_projects_company_project_integration_path(@project, integration), as: :json
    assert_equal %w[10000 10001], response.parsed_body["projects"].pluck("id")

    patch company_project_integration_path(@project, integration), params: { project_ids: [ "10000" ] }
    assert_equal [ "active", [ "10000" ] ], [ integration.reload.status, integration.project_trackers.pluck(:external_scope_id) ]

    get jira_oauth_callback_path, params: { code: "c", state: state }
    assert_equal "This Jira authorization link was already used", flash[:alert]
  end

  test "a callback whose state another user started is refused" do
    other = create(:user, :admin, company: @company)
    state = Oauth::State.encode(owner_type: "Project", owner_id: @project.id, user_id: other.id, return_to: nil,
                                code_verifier: nil, provider: "jira")

    get jira_oauth_callback_path, params: { code: "c", state: state }

    assert_redirected_to root_path
    assert_equal "Invalid or expired Jira authorization", flash[:alert]
  end

  test "testing a Jira connection re-reads it" do
    integration = create(:integration, :jira, :active, project: @project, company: @company)

    post test_connection_company_project_integration_path(@project, integration)

    assert_equal "Connection verified", flash[:notice]
    assert @jira.called?(:myself)
  end
end
