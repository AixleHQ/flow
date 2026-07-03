# frozen_string_literal: true

require "test_helper"

class PersonalMCPWorkflowsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user, :with_company)
    @company = @user.company
    @project = create(:project, company: @company, owner: @user)
    @workflow = create(:workflow, scope: @project)
    @token = @user.regenerate_mcp_token!
  end

  def call_tool(name, args = {}, token: @token)
    post "/mcp",
         params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                   params: { name: name, arguments: args } }.to_json,
         headers: { "Content-Type" => "application/json",
                    "Accept" => "application/json, text/event-stream",
                    "Authorization" => "Bearer #{token}" }
    response.parsed_body
  end

  def payload(body) = JSON.parse(body.dig("result", "content").first["text"])
  def error?(body) = body.dig("result", "isError")

  test "list_workflows lists project-visible workflows" do
    names = payload(call_tool("list_workflows", { project_id: @project.id }))["workflows"].map { |w| w["name"] }
    assert_includes names, @workflow.name
  end

  test "create_workflow then get_workflow and create_workflow_step" do
    created = payload(call_tool("create_workflow", { project_id: @project.id, name: "Built by MCP" }))
    wf_id = created["id"]
    assert Workflow.exists?(wf_id)

    step_body = call_tool("create_workflow_step",
                          { project_id: @project.id, workflow_id: wf_id, name: "Step 1", instructions: "do it" })
    assert_not error?(step_body)

    detail = payload(call_tool("get_workflow", { project_id: @project.id, workflow_id: wf_id }))
    assert_equal 1, detail["steps_count"]
    assert_equal "Step 1", detail["steps"].first["name"]
  end

  test "trigger_workflow starts a run and list/get_workflow_run report it" do
    run_obj = @workflow.runs.create!(project: @project, user: @user, state: "pending")
    WorkflowService.stubs(:start).returns(run_obj)

    body = call_tool("trigger_workflow", { project_id: @project.id, workflow_id: @workflow.id })
    assert_not error?(body)
    assert_equal run_obj.id, payload(body)["run_id"]

    runs = payload(call_tool("list_workflow_runs", { project_id: @project.id }))["runs"]
    assert_includes runs.map { |r| r["id"] }, run_obj.id

    detail = payload(call_tool("get_workflow_run", { project_id: @project.id, run_id: run_obj.id }))
    assert_equal "pending", detail["state"]
  end

  test "a read-only viewer can list but not create workflows" do
    viewer = create(:user, :viewer, company: @company)
    @project.add_collaborator(viewer)
    vtoken = viewer.regenerate_mcp_token!

    assert_not error?(call_tool("list_workflows", { project_id: @project.id }, token: vtoken))

    write = call_tool("create_workflow", { project_id: @project.id, name: "nope" }, token: vtoken)
    assert error?(write)
    assert_match(/not allowed/i, write.dig("result", "content").first["text"])
  end
end
