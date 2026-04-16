# frozen_string_literal: true

require "test_helper"

class Web::Company::RepositoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@user)
  end

  test "index renders repositories page" do
    get company_repositories_path
    assert_inertia_page "Company/Repositories/Index"
  end

  test "create redirects on success" do
    integration = create(:integration, company: @company, connected_by: @user)

    post company_repositories_path, params: {
      repository: { full_name: "org/repo", clone_url: "https://github.com/org/repo.git",
                     source_branch: "main", integration_id: integration.id }
    }
    assert_response :redirect
  end

  test "update redirects on success" do
    integration = create(:integration, company: @company, connected_by: @user)
    repo = create(:repository, integration: integration, scope: @company)

    patch company_repository_path(repo), params: {
      repository: { source_branch: "develop" }
    }
    assert_response :redirect
  end

  test "destroy redirects" do
    integration = create(:integration, company: @company, connected_by: @user)
    repo = create(:repository, integration: integration, scope: @company)

    delete company_repository_path(repo)
    assert_response :redirect
  end
end
