# frozen_string_literal: true

require "test_helper"

class Web::Company::Integrations::GithubSetupControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "creates project-scoped github integration and redirects to the project" do
    token_service = stub(verify_installation: { account_login: "octocat", account_type: "User", target_type: "User" })
    Github::TokenService.stubs(:new).returns(token_service)

    assert_difference("Integration.count", 1) do
      get company_integrations_github_setup_path,
          params: { state: "project:#{@project.id}", installation_id: "12345" }
    end

    integration = Integration.last
    assert_equal @project.id, integration.project_id
    assert_equal "github", integration.provider.to_s
    assert_equal "active", integration.status.to_s
    assert_redirected_to company_project_integrations_path(@project)
  end

  test "blank installation_id redirects to the project without creating an integration" do
    assert_no_difference("Integration.count") do
      get company_integrations_github_setup_path, params: { state: "project:#{@project.id}" }
    end

    assert_redirected_to company_project_integrations_path(@project)
  end

  test "missing state redirects to the projects list and creates nothing" do
    assert_no_difference("Integration.count") do
      get company_integrations_github_setup_path, params: { installation_id: "12345" }
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
          params: { state: "project:#{foreign_project.id}", installation_id: "12345" }
    end

    assert_redirected_to company_projects_path
  end
end
