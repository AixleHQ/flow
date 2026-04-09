# frozen_string_literal: true

require "test_helper"

class Web::Company::SkillsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@user)
  end

  test "index renders skills page" do
    get company_skills_path
    assert_inertia_page "Company/Skills/Index"
  end

  test "create installs skill and redirects" do
    skill = create(:skill, :with_company_scope, scope: @company)
    SkillsRegistryService.stubs(:install).returns(skill)

    post company_skills_path, params: { skill_id: "test-org/skills@skill-1" }
    assert_response :redirect
  end

  test "destroy removes skill and redirects" do
    skill = create(:skill, :with_company_scope, scope: @company)

    delete company_skill_path(skill)
    assert_response :redirect
  end
end
