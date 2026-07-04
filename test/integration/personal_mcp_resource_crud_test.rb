# frozen_string_literal: true

require "test_helper"

# Personal MCP resource CRUD: agents, custom tools, MCP servers, skills.
class PersonalMCPResourceCrudTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user, :with_company)
    @company = @user.company
    @project = create(:project, company: @company, owner: @user)
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
  def text(body) = body.dig("result", "content").map { |c| c["text"] }.join(" ")

  test "agent create / update / delete round-trip" do
    created = payload(call_tool("create_agent", { project_id: @project.id, name: "coder", title: "Coder", persona: "writes code" }))
    id = created["id"]
    assert @project.agents.exists?(id)

    assert_not error?(call_tool("update_agent", { project_id: @project.id, agent_id: id, title: "Senior Coder" }))
    assert_equal "Senior Coder", @project.agents.find(id).title

    assert_not error?(call_tool("delete_agent", { project_id: @project.id, agent_id: id }))
    assert_not @project.agents.exists?(id)
  end

  test "custom tool create / update / delete round-trip" do
    created = payload(call_tool("create_custom_tool",
                                { project_id: @project.id, name: "linter", display_name: "Linter",
                                  docker_image: "linter:1" }))
    id = created["id"]
    assert_equal "db", created["source"]

    assert_not error?(call_tool("update_custom_tool", { project_id: @project.id, tool_id: id, enabled: false }))
    assert_not Tool.find(id).enabled

    assert_not error?(call_tool("delete_custom_tool", { project_id: @project.id, tool_id: id }))
    assert Tool.find(id).deleted?
  end

  test "custom tool create rejects a platform name collision" do
    Tools::Reconciler.run!
    body = call_tool("create_custom_tool",
                     { project_id: @project.id, name: "board_list_tasks", display_name: "x", docker_image: "i:1" })
    assert error?(body)
    assert_match(/collides|already/i, text(body))
  end

  test "MCP server create / update / delete round-trip" do
    created = payload(call_tool("create_mcp_server",
                                { project_id: @project.id, name: "ctx7", url: "https://x/mcp", transport: "http" }))
    id = created["id"]
    assert_equal "custom", created["kind"]

    assert_not error?(call_tool("update_mcp_server", { project_id: @project.id, mcp_server_id: id, enabled: false }))
    assert_not error?(call_tool("delete_mcp_server", { project_id: @project.id, mcp_server_id: id }))
    assert_not MCPServer.exists?(id)
  end

  test "skill search / install / uninstall" do
    SkillsRegistryService.stubs(:search).returns([ { "id" => "s1", "name" => "fmt" } ])
    results = payload(call_tool("search_skill_registry", { project_id: @project.id, query: "fmt" }))["results"]
    assert_equal "s1", results.first["id"]

    skill = create(:skill, scope: @project)
    SkillsRegistryService.stubs(:install).returns(skill)
    installed = payload(call_tool("install_skill", { project_id: @project.id, skill_id: "s1" }))
    assert_equal skill.id, installed["id"]

    assert_not error?(call_tool("uninstall_skill", { project_id: @project.id, skill_id: skill.id }))
    assert_not Skill.exists?(skill.id)
  end

  test "a read-only viewer cannot create resources" do
    viewer = create(:user, :viewer, company: @company)
    @project.add_collaborator(viewer)
    vtoken = viewer.regenerate_mcp_token!

    body = call_tool("create_agent", { project_id: @project.id, name: "x", title: "X", persona: "p" }, token: vtoken)
    assert error?(body)
    assert_match(/not allowed/i, text(body))
  end
end
