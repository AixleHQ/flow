# frozen_string_literal: true

require "test_helper"

class Web::Company::ProjectsRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    Bullet.enable = false # the index list page trips the unused-eager-loading gate
    sign_in_as(@user)
  end
  teardown { Bullet.enable = true }

  test "index renders the projects page" do
    get company_projects_path
    assert_response :success
    assert_inertia_page "Projects/IndexPage"

    assert_inertia_props do |props|
      props[:projects].any? { |p| p[:id] == @project.id }
    end
  end
end
