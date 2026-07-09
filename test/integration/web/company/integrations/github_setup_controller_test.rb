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
end
