# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::RepositoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "index renders repositories page" do
    get company_project_repositories_path(@project)
    assert_inertia_page "Projects/Repositories/RepositoriesPage"
  end

  test "create redirects on success" do
    integration = create(:integration, company: @company, connected_by: @user)

    post company_project_repositories_path(@project), params: {
      repository: { full_name: "org/proj-repo", clone_url: "https://github.com/org/proj-repo.git",
                     source_branch: "main", integration_id: integration.id }
    }
    assert_response :redirect
  end

  test "update redirects on success" do
    integration = create(:integration, company: @company, connected_by: @user)
    repo = create(:repository, integration: integration, scope: @project)

    patch company_project_repository_path(@project, repo), params: {
      repository: { source_branch: "develop" }
    }
    assert_response :redirect
  end

  test "destroy redirects" do
    integration = create(:integration, company: @company, connected_by: @user)
    repo = create(:repository, integration: integration, scope: @project)

    delete company_project_repository_path(@project, repo)
    assert_response :redirect
  end
end
