# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::SkillsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "index renders skills page" do
    get company_project_skills_path(@project)
    assert_inertia_page "Projects/Skills/SkillsPage"
  end

  test "create installs skill and redirects" do
    skill = create(:skill, :with_project_scope, scope: @project)
    SkillsRegistryService.stubs(:install).returns(skill)

    post company_project_skills_path(@project), params: { skill_id: "test-org/skills@skill-1" }
    assert_response :redirect
  end

  test "destroy removes skill and redirects" do
    skill = create(:skill, :with_project_scope, scope: @project)

    delete company_project_skill_path(@project, skill)
    assert_response :redirect
  end
end
