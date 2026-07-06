# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::RepositoriesRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    # visible_for_project surfaces project-scoped records for this project.
    @integration = create(:integration, :github, :active, company: @company, project: @project, connected_by: @user)
    @repository = create(:repository, scope: @project, integration: @integration)
    Bullet.enable = false
    sign_in_as(@user)
  end
  teardown { Bullet.enable = true }

  test "index renders the repositories page" do
    get company_project_repositories_path(@project)
    assert_response :success
    assert_inertia_page "Projects/Repositories/RepositoriesPage"
    assert_inertia_props do |props|
      props[:repositories].size == 1
    end
  end
end
