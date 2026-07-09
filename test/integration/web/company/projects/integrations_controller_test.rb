# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::IntegrationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "index renders integrations page" do
    get company_project_integrations_path(@project)
    assert_inertia_page "Projects/Integrations/IntegrationsPage"
  end

  test "slack_oauth_start authorizes an admin and redirects to Slack consent" do
    get slack_oauth_start_company_project_integrations_path(@project)

    assert_response :redirect
    assert_includes response.location, Slack::Oauth::AUTHORIZE_URL
  end

  test "slack_oauth_start is allowed for a non-admin project owner" do
    owner = create(:user, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    project = create(:project, company: @company, owner: owner)
    sign_in_as(owner)

    get slack_oauth_start_company_project_integrations_path(project)

    assert_response :redirect
    assert_includes response.location, Slack::Oauth::AUTHORIZE_URL
  end

  test "slack_oauth_start is denied for a non-admin, non-owner member" do
    member = create(:user, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(member)

    get slack_oauth_start_company_project_integrations_path(@project)

    # Denied — blocked by project scoping (404) or the integrations policy; either
    # way a non-admin, non-owner is never sent to Slack's consent screen.
    assert_not_equal 200, response.status
    assert_not_includes response.location.to_s, Slack::Oauth::AUTHORIZE_URL
  end

  test "github_app_install redirects to GitHub with a signed state" do
    Settings.github.stubs(:app_slug).returns("aixle-app")

    get github_app_install_company_project_integrations_path(@project)

    assert_response :redirect
    assert_includes response.location, "https://github.com/apps/aixle-app/installations/new?state="
    # The state is the signed Oauth::State blob, NOT the legacy plaintext project:<id>.
    assert_not_includes response.location, "project%3A#{@project.id}"
    assert_not_includes response.location, "project:#{@project.id}"
  end

  test "github_app_install alerts when the GitHub App is not configured" do
    Settings.github.stubs(:app_slug).returns(nil)

    get github_app_install_company_project_integrations_path(@project)

    assert_redirected_to company_project_integrations_path(@project)
    assert_equal "GitHub App is not configured", flash[:alert]
  end

  test "destroy removes integration" do
    integration = create(:integration, company: @company, connected_by: @user, project: @project)

    delete company_project_integration_path(@project, integration)
    assert_response :redirect
  end

  test "create coder integration happy path persists project-scoped record" do
    stub_request(:get, "https://coder.example.com/api/v2/users/me").to_return(
      status: 200,
      body: { id: "user-uuid", username: "alice", email: "alice@example.com" }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    assert_difference("Integration.count", 1) do
      post company_project_integrations_path(@project), params: {
        provider: "coder",
        coderUrl: "https://coder.example.com",
        sessionToken: "tok-1",
        lockTtlMinutes: "60"
      }
    end

    integration = Integration.last
    assert_equal @project.id, integration.project_id
    assert_equal "coder", integration.provider.to_s
    assert_equal "active", integration.status.to_s
    assert_response :redirect
  end

  test "create coder integration sad path persists in error state" do
    stub_request(:get, "https://coder.example.com/api/v2/users/me").to_return(status: 401)

    assert_difference("Integration.count", 1) do
      post company_project_integrations_path(@project), params: {
        provider: "coder",
        coderUrl: "https://coder.example.com",
        sessionToken: "bad-token",
        lockTtlMinutes: "60"
      }
    end

    integration = Integration.last
    assert_equal "error", integration.status.to_s
    assert_response :redirect
  end

  test "create coder integration allows http URL" do
    stub_request(:get, "http://coder.example.com/api/v2/users/me").to_return(
      status: 200,
      body: { id: "user-uuid", username: "alice", email: "alice@example.com" }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    assert_difference("Integration.count", 1) do
      post company_project_integrations_path(@project), params: {
        provider: "coder",
        coderUrl: "http://coder.example.com",
        sessionToken: "tok-1",
        lockTtlMinutes: "60"
      }
    end

    integration = Integration.last
    assert_equal "active", integration.status.to_s
    assert_equal "http://coder.example.com", integration.credentials_data["coder_url"]
    assert_response :redirect
  end
end
