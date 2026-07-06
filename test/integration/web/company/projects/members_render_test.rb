# frozen_string_literal: true

require "test_helper"

# Page render-smoke: the project-scoped Members controller renders a single
# Inertia page (Projects/Members/MembersPage) from #index. Happy-path render
# contract, complementing members_authorization_test.rb (permit/forbid matrix).
class Web::Company::Projects::MembersRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    Bullet.enable = false # list pages trip the unused-eager-loading gate
    sign_in_as(@user)
  end

  teardown { Bullet.enable = true }

  test "index renders the members page with the project owner as a member" do
    get company_project_members_path(@project)

    assert_response :success
    assert_inertia_page "Projects/Members/MembersPage"
  end
end
