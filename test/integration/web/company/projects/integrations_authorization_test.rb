# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for Web::Company::Projects::IntegrationsController,
# via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Web::Company::Projects::IntegrationsPolicy):
#   index?          => project_accessible?   (read)
#   every write     => manage_integrations? = project_writable?
#
# Any member who can write to the project manages its integrations: owner, admin
# and the employee collaborator are allowed, the read-only viewer is denied, and
# non-members are scoped out to 404 before the policy runs. Removing a
# company-wide install stays a company admin's (IntegrationsControllerTest).
#
# Allowed-write response shapes (no vendor stubbing — every real provider path in
# #create hits an external API, so we exercise the only vendor-free branches):
#   slack_oauth_start -> 302 redirect to Slack's consent URL, no flash alert
#                        (default :allowed_write web shape: redirect + nil alert).
#   create (unsupported provider) -> 302 redirect carrying flash[:alert]
#     "Unsupported provider: ..." — a deterministic body-level guard that proves
#     authorization already passed (denied roles never reach the body). Because
#     that alert is NOT the authz denial, we assert it with allowed: :redirect
#     to skip the default "no alert" check.
#   destroy -> 302 redirect with flash[:notice] (not :alert), so the default holds.
class Web::Company::Projects::IntegrationsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @integration = create(:integration, project: @project, company: @company, connected_by: @owner)
  end

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read { get company_project_integrations_path(@project) }
  end

  test "slack_oauth_start is a project write (redirects to Slack)" do
    with_slack_app
    assert_project_write do
      get slack_oauth_start_company_project_integrations_path(@project)
    end
  end

  # An unsupported provider hits the nil-integration branch => 302 + a non-authz
  # alert, proving the allowed role passed authorization and reached the body.
  test "create is a project write" do
    assert_project_write(allowed: :redirect) do
      post company_project_integrations_path(@project), params: { provider: "unsupported" }
    end
  end

  # update carries a non-authz alert for a provider without editable settings
  # (the seeded integration is a GitHub one), which proves the allowed role got
  # past the policy — same shape as the #create case above.
  test "update is a project write" do
    assert_project_write(allowed: :redirect) do
      patch company_project_integration_path(@project, @integration), params: { lockTtlMinutes: "120" }
    end
  end

  # destroy mutates, so build a throwaway integration per allowed-role iteration.
  test "destroy is a project write" do
    assert_project_write do
      delete company_project_integration_path(
        @project, create(:integration, project: @project, company: @company, connected_by: @owner)
      )
    end
  end

  test "jira_oauth_start is a project write (redirects to Atlassian)" do
    with_jira_oauth_app
    assert_project_write do
      get jira_oauth_start_company_project_integrations_path(@project)
    end
  end

  # A missing credential is refused in the body, after authorization passed.
  test "jira_inspect is a project write" do
    assert_project_write(allowed: :unprocessable_content) do
      post jira_inspect_company_project_integrations_path(@project), params: { site_url: "acme.atlassian.net" }, as: :json
    end
  end

  # It answers with the webhook secret.
  test "jira_webhook is a project write" do
    jira = create(:integration, :jira, :active, project: @project, company: @company, connected_by: @owner)
    assert_project_write(allowed: :success) do
      get jira_webhook_company_project_integration_path(@project, jira), as: :json
    end
  end

  test "linear_oauth_start is a project write (redirects to Linear)" do
    with_linear_oauth_app
    assert_project_write do
      get linear_oauth_start_company_project_integrations_path(@project)
    end
  end

  # A missing key is refused in the body, after authorization passed.
  test "linear_inspect is a project write" do
    assert_project_write(allowed: :unprocessable_content) do
      post linear_inspect_company_project_integrations_path(@project), params: {}, as: :json
    end
  end

  test "linear_teams is a project write" do
    stub_linear!
    linear = create(:integration, :linear, :active, project: @project, company: @company, connected_by: @owner)
    assert_project_write(allowed: :success) do
      get linear_teams_company_project_integration_path(@project, linear), as: :json
    end
  end

  # A missing URL is refused in the body, after authorization passed.
  test "youtrack_connect is a project write" do
    assert_project_write(allowed: :unprocessable_content) do
      post youtrack_connect_company_project_integrations_path(@project), params: {}, as: :json
    end
  end

  test "github_projects is a project write" do
    stub_github_projects!
    github = create(:integration, :github_projects, :active, project: @project, company: @company, connected_by: @owner)
    assert_project_write(allowed: :success) do
      get github_projects_company_project_integration_path(@project, github), as: :json
    end
  end

  test "azure_devops_sign_in is a project write (redirects to Microsoft)" do
    with_azure_devops_enabled
    stub_request(:get, %r{#{AZURE_API_HOST}/contoso/_apis/git/repositories})
      .to_return(status: 302, headers: { "WWW-Authenticate" => "Bearer authorization_uri=#{AZURE_TOKEN_HOST}/#{SecureRandom.uuid}" })
    assert_project_write do
      get azure_devops_sign_in_company_project_integrations_path(@project, organization: "contoso")
    end
  end

  test "teams_connect is a project write (redirects back with the approval link)" do
    with_teams_enabled
    assert_project_write do
      post teams_connect_company_project_integrations_path(@project)
    end
  end

  test "teams_package is a project write" do
    with_teams_enabled
    teams = create(:integration, provider: :teams, company: @company, project: nil, connected_by: @owner)
    assert_project_write(allowed: :success) do
      get teams_package_company_project_integration_path(@project, teams)
    end
  end

  test "teams_link is a project write" do
    with_teams_enabled
    teams = create(:integration, provider: :teams, company: @company, project: nil, connected_by: @owner)
    assert_project_write do
      post teams_link_company_project_integration_path(@project, teams)
    end
  end
end
