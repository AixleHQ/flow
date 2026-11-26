# frozen_string_literal: true

require "test_helper"

class Web::Company::Integrations::GithubSetupControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Real cache so an encoded state's single-use nonce survives to #consume
    # (test env is :null_store, which would make every consume miss).
    @cache = ActiveSupport::Cache::MemoryStore.new
    Rails.stubs(:cache).returns(@cache)

    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  # A signed github_setup state, as IntegrationsController#github_app_install mints it.
  def signed_state(project:, user:)
    Oauth::State.encode(
      owner_type: "Project", owner_id: project.id, user_id: user.id,
      return_to: "/", code_verifier: nil, provider: "github_setup"
    )
  end

  def stub_token_service
    Github::TokenService.stubs(:new).returns(
      FakeGithub::TokenService.new(installation: { account_login: "acme", account_type: "Organization",
                                                   target_type: "Organization" })
    )
  end

  def verify_installation_owners!
    Settings.github.stubs(:client_id).returns("Iv1.client")
    Settings.github.stubs(:client_secret).returns("client-secret")
    Settings.github.stubs(:verify_installation_owner).returns(true)
  end

  # GitHub confirms that the person who brought `code` can see the installation.
  def confirm_installation(installation_id, code:)
    ownership = mock("ownership")
    ownership.stubs(:includes?).with(installation_id).returns(true)
    Github::InstallationOwnership.stubs(:new).with(code: code).returns(ownership)
  end

  def github_app_connection(installation_id, **attributes)
    integration = build(:integration, :github, :active, **attributes)
    integration.credentials_data = { installation_id: installation_id }
    integration.tap(&:save!)
  end

  test "creates project-scoped github integration and redirects to the project" do
    token_service = FakeGithub::TokenService.new(
      installation: { account_login: "octocat", account_type: "User", target_type: "User" }
    )
    Github::TokenService.stubs(:new).returns(token_service)

    assert_difference("Integration.count", 1) do
      get company_integrations_github_setup_path,
          params: { state: signed_state(project: @project, user: @user), installation_id: "12345" }
    end

    integration = Integration.last
    assert_equal @project.id, integration.project_id
    assert_equal "github", integration.provider.to_s
    assert_equal "active", integration.status.to_s
    assert token_service.called?(:verify_installation)
    assert_redirected_to company_project_integrations_path(@project)
  end

  test "blank installation_id redirects to the project without creating an integration" do
    assert_no_difference("Integration.count") do
      get company_integrations_github_setup_path, params: { state: signed_state(project: @project, user: @user) }
    end

    assert_redirected_to company_project_integrations_path(@project)
  end

  test "missing state redirects to the projects list and creates nothing" do
    assert_no_difference("Integration.count") do
      get company_integrations_github_setup_path, params: { installation_id: "12345" }
    end

    assert_redirected_to company_projects_path
  end

  test "forged plaintext state is rejected as a misroute and creates nothing" do
    assert_no_difference("Integration.count") do
      get company_integrations_github_setup_path,
          params: { state: "project:#{@project.id}", installation_id: "12345" }
    end

    assert_redirected_to company_projects_path
  end

  test "a link older than ten minutes says it expired" do
    state = signed_state(project: @project, user: @user)

    travel 11.minutes do
      assert_no_difference("Integration.count") do
        get company_integrations_github_setup_path, params: { state: state, installation_id: "12345" }
      end
    end

    assert_redirected_to company_projects_path
    assert_match(/GitHub setup link expired/, flash[:alert])
  end

  test "a state that is not ours is a misroute, not an expiry" do
    get company_integrations_github_setup_path, params: { state: "forged--signature", installation_id: "12345" }

    assert_redirected_to company_projects_path
    assert_equal "Connect a GitHub integration from within a project.", flash[:alert]
  end

  test "inaccessible project redirects to the projects list and creates nothing" do
    foreign_owner = create(:user, company: @company)
    foreign_project = create(:project, company: @company, owner: foreign_owner)
    employee = create(:user, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(employee)

    assert_no_difference("Integration.count") do
      get company_integrations_github_setup_path,
          params: { state: signed_state(project: foreign_project, user: foreign_owner), installation_id: "12345" }
    end

    assert_redirected_to company_projects_path
  end

  test "a replayed state (nonce already consumed) is rejected" do
    Github::TokenService.stubs(:new).returns(
      FakeGithub::TokenService.new(installation: { account_login: "octocat", account_type: "User", target_type: "User" })
    )
    state = signed_state(project: @project, user: @user)

    get company_integrations_github_setup_path, params: { state: state, installation_id: "12345" }
    assert_redirected_to company_project_integrations_path(@project)

    # Same link again: the single-use nonce is gone, so no second integration is created.
    assert_no_difference("Integration.count") do
      get company_integrations_github_setup_path, params: { state: state, installation_id: "67890" }
    end
    assert_redirected_to company_project_integrations_path(@project)
    assert_equal "GitHub setup link expired or already used — start the connection again.", flash[:alert]
  end

  test "a state pinned to a different user is rejected" do
    other = create(:user, company: @company)

    assert_no_difference("Integration.count") do
      # Admin @user is signed in (so the project is accessible), but the state was
      # minted for `other` — the user pin must reject it.
      get company_integrations_github_setup_path,
          params: { state: signed_state(project: @project, user: other), installation_id: "12345" }
    end

    assert_redirected_to company_project_integrations_path(@project)
  end
  test "an installation another company already connected is refused" do
    Github::TokenService.stubs(:new).returns(
      FakeGithub::TokenService.new(installation: { account_login: "victim-org", account_type: "Organization",
                                                   target_type: "Organization" })
    )
    victim_company = create(:company)
    victim_admin = create(:user, :admin, company: victim_company)
    Github::IntegrationService.new(company: victim_company, connected_by: victim_admin,
                                   project: create(:project, company: victim_company, owner: victim_admin))
      .create(installation_id: "424242")

    assert_no_difference("Integration.count") do
      get company_integrations_github_setup_path,
          params: { state: signed_state(project: @project, user: @user), installation_id: "424242" }
    end

    assert_redirected_to company_project_integrations_path(@project)
    assert_equal "This GitHub installation is already connected to another workspace", flash[:alert]
  end

  test "with installation owners verified, an update without a code goes through GitHub's authorization " \
       "and connects an installation another company holds" do
    stub_token_service
    other_company = create(:company)
    github_app_connection("424242", company: other_company)
    verify_installation_owners!

    assert_no_difference("Integration.count") do
      get company_integrations_github_setup_path,
          params: { state: signed_state(project: @project, user: @user), installation_id: "424242", setup_action: "update" }
    end
    authorization = URI(response.location)
    query = Rack::Utils.parse_query(authorization.query)
    assert_equal "https://github.com/login/oauth/authorize", "#{authorization.scheme}://#{authorization.host}#{authorization.path}"
    assert_equal "Iv1.client", query["client_id"]
    assert_equal company_integrations_github_setup_url(protocol: Settings.protocol, host: Settings.domain), query["redirect_uri"]

    confirm_installation("424242", code: "user-code")
    get company_integrations_github_setup_path, params: { code: "user-code", state: query["state"] }

    assert_redirected_to company_project_integrations_path(@project)
    assert_equal "GitHub connected", flash[:notice]
    assert_equal [ other_company.id, @company.id ].sort,
                 Integration.where(provider: :github, github_installation_id: 424_242, status: "active").pluck(:company_id).sort
  end

  test "on the way back from GitHub's authorization, the installation is the one in the signed state" do
    stub_token_service
    verify_installation_owners!
    get company_integrations_github_setup_path,
        params: { state: signed_state(project: @project, user: @user), installation_id: "12345" }
    state = Rack::Utils.parse_query(URI(response.location).query)["state"]

    confirm_installation("12345", code: "user-code")
    get company_integrations_github_setup_path, params: { code: "user-code", state: state, installation_id: "67890" }

    assert_equal [ 12_345 ], @company.integrations.pluck(:github_installation_id)
  end

  test "a person who declines GitHub's authorization is told so and not sent back to it" do
    verify_installation_owners!
    get company_integrations_github_setup_path,
        params: { state: signed_state(project: @project, user: @user), installation_id: "12345" }
    state = Rack::Utils.parse_query(URI(response.location).query)["state"]

    assert_no_difference("Integration.count") do
      get company_integrations_github_setup_path, params: { error: "access_denied", state: state }
    end

    assert_redirected_to company_project_integrations_path(@project)
    assert_equal "GitHub did not confirm your access to this installation — connect GitHub again.", flash[:alert]
  end

  test "a new installation that already carries the person's code connects without another trip to GitHub" do
    stub_token_service
    verify_installation_owners!
    confirm_installation("12345", code: "install-code")

    assert_difference("Integration.count", 1) do
      get company_integrations_github_setup_path,
          params: { state: signed_state(project: @project, user: @user), installation_id: "12345", code: "install-code" }
    end

    assert_redirected_to company_project_integrations_path(@project)
    assert_equal "GitHub connected", flash[:notice]
  end

  test "records the installation's account so repository owners can be checked" do
    Github::TokenService.stubs(:new).returns(
      FakeGithub::TokenService.new(installation: { account_login: "octocat", account_type: "User", target_type: "User" })
    )

    get company_integrations_github_setup_path,
        params: { state: signed_state(project: @project, user: @user), installation_id: "12345" }

    assert_equal "octocat", Integration.last.github_account_login
  end
end
