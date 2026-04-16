# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::AgentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "index renders agents page" do
    get company_project_agents_path(@project)
    assert_inertia_page "Projects/Agents/AgentsPage"
  end

  test "create redirects on success" do
    post company_project_agents_path(@project), params: {
      agent: { name: "projagent", title: "Proj Agent", persona: "helpful" }
    }
    assert_response :redirect
  end

  test "update redirects on success" do
    agent = Agent.create!(name: "pa1", title: "PA1", persona: "p", source: :custom, scope: @project)

    patch company_project_agent_path(@project, agent), params: {
      agent: { title: "Updated" }
    }
    assert_response :redirect
  end

  test "destroy redirects" do
    agent = Agent.create!(name: "pa2", title: "PA2", persona: "p", source: :custom, scope: @project)

    delete company_project_agent_path(@project, agent)
    assert_response :redirect
  end
end
