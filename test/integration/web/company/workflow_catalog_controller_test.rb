# frozen_string_literal: true

require "test_helper"

class Web::Company::WorkflowCatalogControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "index renders catalog with published workflows" do
    create_list(:workflow, 2, scope: @company, published_at: Time.current, published_by: @user)
    create(:workflow, scope: @company)

    get company_workflow_catalog_index_path
    assert_inertia_page "Company/WorkflowCatalog/IndexPage"
  end

  test "duplicate creates workflow copy in target project" do
    workflow = create(:workflow, scope: @company, published_at: Time.current, published_by: @user)
    create(:step, workflow: workflow, position: 1)
    create(:step, workflow: workflow, position: 2)

    assert_difference "Workflow.count", 1 do
      post duplicate_company_workflow_catalog_path(workflow), params: { project_id: @project.id }
    end

    assert_response :redirect
    copy = Workflow.last
    assert_equal @project.id, copy.scope_id
    assert_equal "Project", copy.scope_type
    assert_equal 2, copy.steps.count
  end

  test "duplicate copies workflow dependencies into the project without copying secrets" do
    agent = create(:agent, scope: @company, name: "helper", title: "Helper", persona: "Helps.")
    skill = create(:skill, scope: @company)
    mcp = create(:mcp_server, scope: @company, name: "context7",
                              headers: { "Authorization" => "Bearer config_item:API_KEY" })
    workflow = create(:workflow, scope: @company, published_at: Time.current, published_by: @user)
    create(:step, workflow: workflow, position: 1, agent_id: agent.id,
                  skill_ids: [ skill.id ], mcp_server_ids: [ mcp.id ])

    assert_difference [ "@project.agents.count", "Skill.for_project(@project).count",
                        "MCPServer.for_project(@project).count" ], 1 do
      assert_no_difference "ConfigItem.count" do
        post duplicate_company_workflow_catalog_path(workflow), params: { project_id: @project.id }
      end
    end

    assert_response :redirect
    copy = Workflow.last
    copied_step = copy.steps.order(:position).first
    assert_equal @project.id, Agent.find(copied_step.agent_id).scope_id
    assert_equal @project.id, Skill.find(copied_step.skill_ids.first).scope_id
    new_mcp = MCPServer.find(copied_step.mcp_server_ids.first)
    assert_equal @project.id, new_mcp.scope_id
    # env/headers copied verbatim — config_item:NAME reference preserved
    assert_equal "Bearer config_item:API_KEY", new_mcp.headers["Authorization"]
  end

  test "duplicate is idempotent: posting twice does not duplicate resources or config items" do
    agent = create(:agent, scope: @company, name: "helper", title: "Helper", persona: "Helps.")
    workflow = create(:workflow, scope: @company, published_at: Time.current, published_by: @user)
    create(:step, workflow: workflow, position: 1, agent_id: agent.id)

    post duplicate_company_workflow_catalog_path(workflow), params: { project_id: @project.id }

    assert_no_difference [ "@project.agents.count", "ConfigItem.count" ] do
      post duplicate_company_workflow_catalog_path(workflow), params: { project_id: @project.id }
    end
  end

  test "duplicate rejects non-published workflow" do
    workflow = create(:workflow, scope: @company)

    post duplicate_company_workflow_catalog_path(workflow), params: { project_id: @project.id }
    assert_response :redirect
    assert_match(/not found/, flash[:alert])
  end
end
