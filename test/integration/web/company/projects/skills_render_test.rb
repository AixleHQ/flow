# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::SkillsRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    Bullet.enable = false
    sign_in_as(@user)
  end

  teardown { Bullet.enable = true }

  test "index renders the skills page with visible skills" do
    skill = create(:skill, scope: @project)

    get company_project_skills_path(@project)
    assert_response :success
    assert_inertia_page "Projects/Skills/SkillsPage"

    assert_inertia_props do |props|
      props[:skills].any? { |s| s[:id] == skill.id }
    end
  end
end
