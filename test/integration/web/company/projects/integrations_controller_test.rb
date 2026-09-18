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

  test "index tells the page whether the GitHub App is configured" do
    Settings.github.stubs(:app_slug).returns("aixle-app")
    Settings.github.stubs(:app_id).returns("999")

    get company_project_integrations_path(@project)

    assert_inertia_props { |props| props[:github][:appConfigured] == true }
  end

  test "index reports the GitHub App as unconfigured when the deployment has none" do
    Settings.github.stubs(:app_slug).returns(nil)

    get company_project_integrations_path(@project)

    assert_inertia_props { |props| props[:github][:appConfigured] == false }
  end

  test "create github in PAT mode activates without an App or an installation" do
    Settings.github.stubs(:app_id).returns(nil)
    Settings.github.stubs(:app_slug).returns(nil)
    stub_request(:get, "https://api.github.com/user").to_return(
      status: 200,
      headers: { "Content-Type" => "application/json", "X-OAuth-Scopes" => "repo" },
      body: { id: 4_242, login: "octodev", type: "User" }.to_json
    )

    assert_difference("Integration.count", 1) do
      post company_project_integrations_path(@project), params: {
        provider: "github",
        authMode: "pat",
        personalAccessToken: "ghp_developer_token"
      }
    end

    assert_redirected_to company_project_integrations_path(@project)
    integration = Integration.order(:created_at).last
    assert integration.active?
    assert integration.github_pat?
    assert_equal @project.id, integration.project_id
    assert_equal "octodev", integration.name
  end

  test "create github in PAT mode reports a rejected token as a field error" do
    stub_request(:get, "https://api.github.com/user").to_return(
      status: 401,
      headers: { "Content-Type" => "application/json" },
      body: { message: "Bad credentials" }.to_json
    )

    assert_no_difference("Integration.count") do
      post company_project_integrations_path(@project), params: {
        provider: "github",
        authMode: "pat",
        personalAccessToken: "ghp_revoked"
      }
    end

    assert_redirected_to company_project_integrations_path(@project)
    assert_match(/invalid, revoked or expired/, Array(session["inertia_errors"][:personal_access_token]).to_sentence)
  end

  # The declared mode decides which credential is read. A token posted
  # alongside an installation id must not be able to walk the App path, or a
  # mode switch in the dialog could submit the other path's credential.
  test "create github in PAT mode ignores an installation id posted with it" do
    stub_request(:get, "https://api.github.com/user").to_return(
      status: 200,
      headers: { "Content-Type" => "application/json", "X-OAuth-Scopes" => "repo" },
      body: { id: 4_242, login: "octodev", type: "User" }.to_json
    )

    post company_project_integrations_path(@project), params: {
      provider: "github",
      authMode: "pat",
      installationId: "12345",
      personalAccessToken: "ghp_developer_token"
    }

    integration = Integration.order(:created_at).last
    assert integration.github_pat?
    assert_nil integration.installation_id
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

  # The :coder factory trait rewrites `settings` in an after(:build) hook, so a
  # test that needs specific settings has to merge them after create.
  def create_coder_integration(project: @project, **settings)
    integration = create(:integration, :coder, :active, company: @company, project: project, connected_by: @user)
    integration.update!(settings: integration.settings.merge(settings)) if settings.any?
    integration
  end

  test "update saves coder settings without touching credentials" do
    integration = create_coder_integration("machine_prefix" => "old-prefix")
    credentials_before = integration.credentials_data

    patch company_project_integration_path(@project, integration), params: {
      defaultTemplate: "aws-ec2-spot-v1",
      machinePrefix:   "aixle-prod",
      lockTtlMinutes:  "120"
    }

    assert_response :redirect
    integration.reload
    assert_equal "aws-ec2-spot-v1", integration.coder_default_template
    assert_equal "aixle-prod", integration.coder_machine_prefix
    assert_equal 120, integration.coder_lock_ttl_minutes
    assert_equal credentials_before, integration.credentials_data
  end

  test "update clears a blank template so the pool stops growing" do
    integration = create_coder_integration("default_template" => "aws-ec2-spot-v1")

    patch company_project_integration_path(@project, integration), params: {
      defaultTemplate: "", machinePrefix: "", lockTtlMinutes: "120"
    }

    assert_response :redirect
    assert_nil integration.reload.coder_default_template
  end

  test "update rejects a non-positive lock TTL and keeps the stored settings" do
    integration = create_coder_integration("machine_prefix" => "aixle-prod")

    patch company_project_integration_path(@project, integration), params: {
      machinePrefix: "changed", lockTtlMinutes: "0"
    }

    assert_response :redirect
    assert_match(/Lock TTL minutes must be a positive number/, flash[:alert])
    assert_equal "aixle-prod", integration.reload.coder_machine_prefix
  end

  test "update refuses a provider that has no editable settings" do
    integration = create(:integration, company: @company, project: @project, connected_by: @user)

    patch company_project_integration_path(@project, integration), params: { lockTtlMinutes: "120" }

    assert_response :redirect
    assert_match(/Only Coder integrations have editable settings/, flash[:alert])
  end

  test "update does not reach a company-wide integration from a project page" do
    integration = create_coder_integration(project: nil)

    patch company_project_integration_path(@project, integration), params: { lockTtlMinutes: "5" }

    assert_response :not_found
    assert_equal 60, integration.reload.coder_lock_ttl_minutes
  end
end
