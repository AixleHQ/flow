# frozen_string_literal: true

require "test_helper"

# The Aixle Builder is served the personal MCP tools through its own session's
# MCP endpoint, pinned to the session's project and run as the session's user.
class BuilderMcpToolsTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, :aixle_builder, :started, user: @user, project: @project)

    @foreign_user = create(:user, company: create(:company))
    @foreign_project = create(:project, company: @foreign_user.companies.first, owner: @foreign_user)
    @foreign_workflow = create(:workflow, scope: @foreign_project, name: "Foreign")
  end

  test "a builder session lists the project tools without a project_id parameter" do
    tools = listed_tools(rpc("tools/list"))
    by_name = tools.index_by { |t| t["name"] }

    assert_includes by_name.keys, "create_workflow"
    assert_includes by_name.keys, "create_workflow_trigger"
    assert_includes by_name.keys, "validate_workflow"
    assert_includes by_name.keys, "get_session_log"
    assert_not_includes by_name.keys, "list_companies"
    assert_not_includes by_name.keys, "create_project"
    assert_not_includes by_name.keys, "create_config_item"
    assert_not_includes by_name.keys, "create_custom_tool"
    assert tools.none? { |t| t.dig("inputSchema", "properties")&.key?("project_id") }
  end

  test "a plain agent session is not served the builder tools" do
    @session = create(:terminal_session, :agent_session, :started, user: @user, project: @project)

    names = listed_tools(rpc("tools/list")).map { |t| t["name"] }

    assert_not_includes names, "create_workflow"
  end

  test "a created workflow lands in the session's project whatever project_id is passed" do
    body = call_tool("create_workflow", name: "Onboarding", project_id: @foreign_project.id)

    assert_not body.dig("result", "isError"), text(body)
    assert Workflow.visible_for_project(@project).exists?(name: "Onboarding")
    assert_not Workflow.visible_for_project(@foreign_project).exists?(name: "Onboarding")
    activity = @session.reload.metadata["builder_activities"].last
    assert_equal({ "action" => "create_workflow", "entity_type" => "Workflow", "entity_name" => "Onboarding" },
                 activity.slice("action", "entity_type", "entity_name"))
  end

  test "another project's records read as not found" do
    body = call_tool("get_workflow", workflow_id: @foreign_workflow.id)
    assert body.dig("result", "isError")

    body = call_tool("delete_workflow", workflow_id: @foreign_workflow.id)
    assert body.dig("result", "isError")
    assert_nil @foreign_workflow.reload.deleted_at
  end

  test "a second project param cannot reach outside the pinned project" do
    sibling = create(:project, company: @company, owner: @user)
    workflow = create(:workflow, scope: @project, name: "Source")

    body = call_tool("duplicate_workflow", workflow_id: workflow.id, target_project_id: sibling.id)

    assert body.dig("result", "isError")
    assert_match(/not found/i, text(body))
    assert_not Workflow.visible_for_project(sibling).exists?(name: "Source")
  end

  test "the tools act with the session user's permissions" do
    viewer = create(:user, company: @company, membership_role: "viewer")
    @project.project_collaborators.create!(user: viewer)
    @session = create(:terminal_session, :aixle_builder, :started, user: viewer, project: @project)

    body = call_tool("create_workflow", name: "By viewer")

    assert body.dig("result", "isError")
    assert_match(/not allowed/i, text(body))
    assert_not Workflow.exists?(name: "By viewer")
  end

  private

  def rpc(method, params = {})
    post "/action_mcp",
         params: { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json,
         headers: { "Content-Type" => "application/json",
                    "Accept" => "application/json, text/event-stream",
                    "X-Session-Key" => @session.mcp_key }
    response.parsed_body
  end

  def call_tool(name, **arguments)
    rpc("tools/call", { name: name, arguments: arguments })
  end

  def listed_tools(body)
    body.dig("result", "tools")
  end

  def text(body)
    Array(body.dig("result", "content")).map { |c| c["text"] }.join("\n")
  end
end
