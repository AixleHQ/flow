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

  test "destroy archives the agent, and the index lists it as archived" do
    agent = Agent.create!(name: "pa2", title: "PA2", persona: "p", source: :custom, scope: @project)

    delete company_project_agent_path(@project, agent)
    assert_redirected_to company_project_agents_path(@project)
    assert_equal "Agent archived", flash[:notice]
    assert agent.reload.archived?

    get company_project_agents_path(@project)
    assert_empty inertia.props[:agents]
    assert_equal [ agent.id ], inertia.props[:archivedAgents].pluck(:id)
  end

  test "destroy refuses an agent a workflow step uses, and says where" do
    agent = Agent.create!(name: "pa3", title: "PA3", persona: "p", source: :custom, scope: @project)
    workflow = create(:workflow, scope: @project, name: "Release")
    create(:step, workflow: workflow, name: "Build", agent: agent)

    delete company_project_agent_path(@project, agent)

    assert_response :redirect
    assert_match(/Release → Build/, flash[:alert])
    assert_not agent.reload.archived?
  end

  test "update from a stale version is refused and changes nothing" do
    agent = Agent.create!(name: "pa4", title: "PA4", persona: "p", source: :custom, scope: @project)
    Versions.save!(agent, actor: Versions::Actor.ui(@user)) { agent.update!(title: "Newer") }

    patch company_project_agent_path(@project, agent), params: { agent: { title: "Lost" }, base_version: 1 }

    assert_match(/newer version/, flash[:alert])
    assert_equal "Newer", agent.reload.title
  end
end
