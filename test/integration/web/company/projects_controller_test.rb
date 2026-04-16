# frozen_string_literal: true

require "test_helper"

class Web::Company::ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@user)
  end

  test "index renders projects page" do
    get company_projects_path
    assert_inertia_page "Projects/IndexPage"
  end

  test "create redirects on success" do
    post company_projects_path, params: { project: { name: "Test Project", description: "A test" } }
    assert_response :redirect
  end

  test "destroy redirects on success" do
    project = create(:project, company: @company, owner: @user)
    delete company_project_path(project)
    assert_response :redirect
  end
end
