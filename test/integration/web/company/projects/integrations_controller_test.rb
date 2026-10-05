# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::IntegrationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    resolve_hosts_publicly!
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "index renders integrations page" do
    get company_project_integrations_path(@project)
    assert_inertia_page "Projects/Integrations/IntegrationsPage"
  end

  test "slack_oauth_start refuses on a deployment with no Slack app" do
    with_slack_app(client_id: "")

    get slack_oauth_start_company_project_integrations_path(@project)

    assert_redirected_to company_project_integrations_path(@project)
    assert_equal "Slack's app is not configured", flash[:alert]
  end

  test "index offers Slack only when the deployment has a Slack app" do
    with_slack_app(client_id: "")
    get company_project_integrations_path(@project)
    assert_inertia_props { |props| props[:slack][:enabled] == false }

    with_slack_app
    get company_project_integrations_path(@project)
    assert_inertia_props { |props| props[:slack][:enabled] == true }
  end

  test "teams_connect hands the admin an approval link for their Microsoft 365 administrator" do
    with_teams_enabled
    get company_project_integrations_path(@project)
    assert_inertia_props { |props| props[:teams][:enabled] == true }

    assert_difference -> { @company.integrations.where(provider: :teams).count }, 1 do
      post teams_connect_company_project_integrations_path(@project)
    end

    assert_redirected_to company_project_integrations_path(@project)
    token = flash[:teams_approval_url].split("/").last
    assert_equal @company.integrations.find_by!(provider: :teams), Teams::Connection.find_by_token(token)
  end

  test "teams_link hands out a fresh approval link for an existing connection" do
    with_teams_enabled
    teams, old = Teams::Connection.start!(company: @company, user: @user)

    post teams_link_company_project_integration_path(@project, teams)

    assert_redirected_to company_project_integrations_path(@project)
    assert_equal teams, Teams::Connection.find_by_token(flash[:teams_approval_url].split("/").last)
    assert_nil Teams::Connection.find_by_token(old)
  end

  test "teams_connect refuses on a deployment with no Teams bot" do
    post teams_connect_company_project_integrations_path(@project)

    assert_redirected_to company_project_integrations_path(@project)
    assert_match(/not configured/, flash[:alert])
    assert_not @company.integrations.exists?(provider: :teams)
  end

  test "teams_package hands out the app for a Teams connection the project can see" do
    with_teams_enabled
    teams = create(:integration, provider: :teams, company: @company, project: nil, connected_by: @user)
    github = create(:integration, project: @project, company: @company, connected_by: @user)

    get teams_package_company_project_integration_path(@project, teams)
    assert_equal "application/zip", response.media_type

    get teams_package_company_project_integration_path(@project, github)
    assert_response :not_found
  end

  # A company-wide install serves every project and has no page of its own.
  test "a company admin removes a company-wide integration from a project page" do
    slack = create(:integration, provider: :slack, company: @company, project: nil, connected_by: @user)

    delete company_project_integration_path(@project, slack)

    assert_redirected_to company_project_integrations_path(@project)
    assert_not Integration.exists?(slack.id)
  end

  test "a project owner who is not a company admin cannot remove a company-wide integration" do
    owner = create(:user, :employee, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    project = create(:project, company: @company, owner: owner)
    slack = create(:integration, provider: :slack, company: @company, project: nil, connected_by: @user)
    sign_in_as(owner)

    delete company_project_integration_path(project, slack)

    assert_equal "Only a company admin can remove a company-wide integration", flash[:alert]
    assert Integration.exists?(slack.id)
  end

  test "slack_oauth_start authorizes an admin and redirects to Slack consent" do
    with_slack_app
    get slack_oauth_start_company_project_integrations_path(@project)

    assert_response :redirect
    assert_includes response.location, Slack::Oauth::AUTHORIZE_URL
  end

  test "slack_oauth_start is allowed for a non-admin project owner" do
    with_slack_app
    owner = create(:user, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    project = create(:project, company: @company, owner: owner)
    sign_in_as(owner)

    get slack_oauth_start_company_project_integrations_path(project)

    assert_response :redirect
    assert_includes response.location, Slack::Oauth::AUTHORIZE_URL
  end

  test "slack_oauth_start is denied for a non-admin, non-owner member" do
    with_slack_app
    member = create(:user, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(member)

    get slack_oauth_start_company_project_integrations_path(@project)

    # Denied — blocked by project scoping (404) or the integrations policy; either
    # way a non-admin, non-owner is never sent to Slack's consent screen.
    assert_not_equal 200, response.status
    assert_not_includes response.location.to_s, Slack::Oauth::AUTHORIZE_URL
  end

  def stub_github_app(app_slug: "aixle-app", app_id: "999", private_key: "-----BEGIN RSA PRIVATE KEY-----")
    Settings.github.stubs(:app_slug).returns(app_slug)
    Settings.github.stubs(:app_id).returns(app_id)
    Settings.github.stubs(:private_key).returns(private_key)
    Settings.github.stubs(:private_key_path).returns(nil)
  end

  test "github_app_install redirects to GitHub with a signed state" do
    stub_github_app

    get github_app_install_company_project_integrations_path(@project)

    assert_response :redirect
    assert_includes response.location, "https://github.com/apps/aixle-app/installations/new?state="
    # The state is the signed Oauth::State blob, NOT the legacy plaintext project:<id>.
    assert_not_includes response.location, "project%3A#{@project.id}"
    assert_not_includes response.location, "project:#{@project.id}"
  end

  test "github_app_install alerts when the GitHub App is not configured" do
    stub_github_app(app_slug: nil)

    get github_app_install_company_project_integrations_path(@project)

    assert_redirected_to company_project_integrations_path(@project)
    assert_equal "GitHub App is not configured", flash[:alert]
  end

  test "index tells the page whether the GitHub App is configured" do
    stub_github_app

    get company_project_integrations_path(@project)

    assert_inertia_props { |props| props[:github][:appConfigured] == true }
  end

  test "index reports the GitHub App as unconfigured when the deployment has none" do
    stub_github_app(app_slug: nil)

    get company_project_integrations_path(@project)

    assert_inertia_props { |props| props[:github][:appConfigured] == false }
  end

  # Without the key every installation would only end up as a connection in error.
  test "index reports the GitHub App as unconfigured without its private key" do
    stub_github_app(private_key: "")

    get company_project_integrations_path(@project)

    assert_inertia_props { |props| props[:github][:appConfigured] == false }
  end

  # App installations arrive only on GitHub's post-install redirect.
  test "create github outside PAT mode connects nothing" do
    other = create(:project, company: @company, owner: @user)
    held = create(:integration, :github, :active, company: @company, connected_by: @user, project: other)

    assert_no_difference("Integration.count") do
      post company_project_integrations_path(@project), params: {
        provider: "github", installationId: held.installation_id
      }
    end

    assert_redirected_to company_project_integrations_path(@project)
    assert_match(/install on GitHub/, flash[:alert])
  end

  test "test_connection re-verifies a GitHub connection" do
    integration = create(:integration, :github, company: @company, connected_by: @user, project: @project,
                                                status: :error, settings: { "error" => "Bad credentials" })
    Github::TokenService.stubs(:new).returns(FakeGithub::TokenService.new)

    post test_connection_company_project_integration_path(@project, integration)

    assert_redirected_to company_project_integrations_path(@project)
    assert_equal "Connection verified", flash[:notice]
    assert integration.reload.active?
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

  def stub_gitlab(user: { id: 152, username: "alice", name: "Alice", email: nil }, verify_error: nil)
    Gitlab::TokenService.stubs(:new).returns(Fakes::FakeGitlabService.new(user: user, verify_error: verify_error))
  end

  test "create gitlab connects and names the account" do
    stub_gitlab

    assert_difference("Integration.count", 1) do
      post company_project_integrations_path(@project), params: { provider: "gitlab", personalAccessToken: "glpat-ok" }
    end

    assert_redirected_to company_project_integrations_path(@project)
    assert_equal "GitLab connected as alice", flash[:notice]
    assert_equal @project.id, Integration.last.project_id
  end

  test "create gitlab again for the same account renews the connection" do
    stub_gitlab
    post company_project_integrations_path(@project), params: { provider: "gitlab", personalAccessToken: "glpat-1" }

    assert_no_difference("Integration.count") do
      post company_project_integrations_path(@project), params: { provider: "gitlab", personalAccessToken: "glpat-2" }
    end
    assert_equal "glpat-2", Integration.last.credentials_data["personal_access_token"]
  end

  # The dialog stays open on a validation error; a flash would close it.
  test "create gitlab answers a refused token with a field error and saves nothing" do
    stub_gitlab(verify_error: Gitlab::TokenService::AuthenticationError.new("GitLab rejected this token."))

    assert_no_difference("Integration.count") do
      post company_project_integrations_path(@project), params: { provider: "gitlab", personalAccessToken: "glpat-bad" }
    end

    assert_redirected_to company_project_integrations_path(@project)
    assert_equal "GitLab rejected this token.", Array(session["inertia_errors"][:personal_access_token]).to_sentence
  end

  test "create gitlab reports an unreachable GitLab instead of failing" do
    stub_gitlab(verify_error: Gitlab::TokenService::ConnectionError.new("Could not reach GitLab at https://gitlab.example.com/api/v4 (SocketError)."))

    post company_project_integrations_path(@project), params: { provider: "gitlab", personalAccessToken: "glpat-x" }

    assert_redirected_to company_project_integrations_path(@project)
    assert_match(/Could not reach GitLab/, Array(session["inertia_errors"][:personal_access_token]).to_sentence)
  end

  test "update replaces a gitlab token in place" do
    stub_gitlab
    integration = create(:integration, :gitlab, :error, company: @company, project: @project, name: "alice")

    patch company_project_integration_path(@project, integration), params: { personalAccessToken: "glpat-new" }

    assert_redirected_to company_project_integrations_path(@project)
    integration.reload
    assert integration.active?
    assert_equal "glpat-new", integration.credentials_data["personal_access_token"]
  end

  test "update keeps the gitlab token GitLab refuses to replace it with" do
    stub_gitlab(verify_error: Gitlab::TokenService::AuthenticationError.new("GitLab rejected this token."))
    integration = create(:integration, :gitlab, :active, company: @company, project: @project, name: "alice")
    token = integration.credentials_data["personal_access_token"]

    patch company_project_integration_path(@project, integration), params: { personalAccessToken: "glpat-bad" }

    assert_equal "GitLab rejected this token.", Array(session["inertia_errors"][:personal_access_token]).to_sentence
    assert_equal token, integration.reload.credentials_data["personal_access_token"]
  end

  test "test_connection marks a gitlab connection whose token GitLab refuses" do
    stub_gitlab(verify_error: Gitlab::TokenService::AuthenticationError.new("GitLab rejected this token."))
    integration = create(:integration, :gitlab, :active, company: @company, project: @project, name: "alice")

    post test_connection_company_project_integration_path(@project, integration)

    assert_equal "Connection failed: GitLab rejected this token.", flash[:alert]
    assert integration.reload.error?
  end

  test "test_connection verifies a coder connection" do
    integration = create_coder_integration
    stub_request(:get, "https://coder.example.com/api/v2/users/me").to_return(
      status: 200, body: { id: integration.coder_user_id, username: "test-user" }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    post test_connection_company_project_integration_path(@project, integration)

    assert_equal "Connection verified", flash[:notice]
    assert integration.reload.settings["last_verified_at"].present?
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

  test "create coder integration sad path saves nothing and keeps the dialog open" do
    stub_request(:get, "https://coder.example.com/api/v2/users/me").to_return(status: 401)

    assert_no_difference("Integration.count") do
      post company_project_integrations_path(@project), params: {
        provider: "coder",
        coderUrl: "https://coder.example.com",
        sessionToken: "bad-token",
        lockTtlMinutes: "60"
      }
    end

    assert_redirected_to company_project_integrations_path(@project)
    assert_match(/HTTP 401/, Array(session["inertia_errors"][:coder]).to_sentence)
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

  test "update replaces a coder session token without touching the pool settings" do
    integration = create_coder_integration("machine_prefix" => "aixle-prod")
    stub_request(:get, "https://coder.example.com/api/v2/users/me").to_return(
      status: 200, body: { id: integration.coder_user_id, username: "test-user" }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    patch company_project_integration_path(@project, integration), params: { sessionToken: "tok-new" }

    assert_equal "Token replaced on Coder (test-user)", flash[:notice]
    integration.reload
    assert_equal "tok-new", integration.credentials_data["session_token"]
    assert_equal "aixle-prod", integration.coder_machine_prefix
    assert_equal 60, integration.coder_lock_ttl_minutes
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
