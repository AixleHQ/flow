# frozen_string_literal: true

require "test_helper"

# Page render-smoke: the project-scoped Agents controller renders a single
# Inertia page (Projects/Agents/AgentsPage) from #index. Happy-path render
# contract, complementing agents_authorization_test.rb (permit/forbid matrix).
class Web::Company::Projects::AgentsRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    Bullet.enable = false # list pages trip the unused-eager-loading gate
    sign_in_as(@user)
  end

  teardown { Bullet.enable = true }

  test "index renders the agents page with the project's agents" do
    agent = create(:agent, scope: @project)

    get company_project_agents_path(@project)

    assert_response :success
    assert_inertia_page "Projects/Agents/AgentsPage"
    assert_inertia_props do |props|
      props[:agents].any? { |a| a[:id] == agent.id }
    end
  end
end
