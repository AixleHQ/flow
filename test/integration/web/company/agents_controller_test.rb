# frozen_string_literal: true

require "test_helper"

class Web::Company::AgentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@user)
  end

  test "index renders agents page" do
    get company_agents_path
    assert_inertia_page "Company/Agents/Index"
  end

  test "create redirects on success" do
    post company_agents_path, params: {
      agent: { name: "myagent", title: "My Agent", persona: "helpful" }
    }
    assert_response :redirect
  end

  test "update redirects on success" do
    agent = Agent.create!(name: "a1", title: "A1", persona: "p", source: :custom, scope: @company)

    patch company_agent_path(agent), params: {
      agent: { title: "Updated Agent" }
    }
    assert_response :redirect
  end

  test "destroy redirects" do
    agent = Agent.create!(name: "a2", title: "A2", persona: "p", source: :custom, scope: @company)

    delete company_agent_path(agent)
    assert_response :redirect
  end
end
