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

  test "destroy succeeds for a company admin who is not the project owner" do
    owner = create(:user, :employee, :onboarding_completed, company: @company)
    project = create(:project, company: @company, owner: owner)

    delete company_project_path(project)

    assert_response :redirect
    assert_not Project.exists?(project.id)
  end

  test "destroy succeeds for the project owner who is not an admin" do
    owner = create(:user, :employee, :onboarding_completed, company: @company,
                                                             password: AuthHelper::TEST_PASSWORD)
    project = create(:project, company: @company, owner: owner)
    sign_in_as(owner)

    delete company_project_path(project)

    assert_response :redirect
    assert_not Project.exists?(project.id)
  end

  test "destroy is denied for a collaborator who is neither owner nor admin" do
    owner = create(:user, :employee, :onboarding_completed, company: @company)
    project = create(:project, company: @company, owner: owner)
    collaborator = create(:user, :employee, :onboarding_completed, company: @company,
                                                                    password: AuthHelper::TEST_PASSWORD)
    project.add_collaborator(collaborator)
    sign_in_as(collaborator)

    delete company_project_path(project)

    # Denial UX is a 302 redirect + not-authorized alert (see ai/research design doc, DECISION 1),
    # not a literal 403. The redirect_back falls back to root_path because the test sends no Referer.
    assert_response :redirect
    assert_equal "You are not authorized to perform this action.", flash[:alert]
    assert Project.exists?(project.id)
  end
end
