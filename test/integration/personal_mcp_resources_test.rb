# frozen_string_literal: true

require "test_helper"

class PersonalMCPResourcesTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
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

  test "list_integrations returns project-visible integrations with status" do
    create(:integration, company: @company, project: @project, provider: :slack,
                         status: :active, connected_by: @user)

    rows = payload(call_tool("list_integrations", { project_id: @project.id }))["integrations"]
    slack = rows.find { |i| i["provider"] == "slack" }
    assert_equal "active", slack["status"]
  end

  test "get_integration_setup_url returns the project integrations page URL, no credentials" do
    body = call_tool("get_integration_setup_url", { project_id: @project.id, provider: "slack" })
    data = payload(body)
    assert_match %r{/company/projects/#{@project.id}/integrations}, data["setup_url"]
    assert_match(/slack/i, data["instructions"])
    refute_includes data.keys, "credentials"
  end

  # The regression: chaining `.ui_visible` onto `visible_for_project` left only
  # project-scoped custom tools, so a project without any answered `[]`.
  test "list_project_tools lists attachable platform tools for a project with no custom tools" do
    Tools::Reconciler.run!

    data = payload(call_tool("list_project_tools", { project_id: @project.id }))
    platform = data["tools"].select { |t| t["source"] == "code" }
    names = platform.map { |t| t["name"] }

    assert_not_empty platform
    assert_includes names, "board_create_task"
    assert_equal data["tools"].size, data["tools_count"]
    # Builder meta_* tools are not attachable and stay out of the picker set.
    assert_not_includes names, "meta_list_tools"

    row = platform.find { |t| t["name"] == "board_create_task" }
    assert_equal "Board Create Task", row["display_name"]
    assert_match(/board task/i, row["description"])
    assert_includes row["tags"], "board"
    assert row["enabled"]
  end

  test "list_project_tools lists custom tools with their metadata" do
    Tools::Reconciler.run!
    create(:tool, scope: @project, name: "my_linter", display_name: "My Linter",
                  description: "Runs the house linter.", docker_image: "l:1")

    tools = payload(call_tool("list_project_tools", { project_id: @project.id }))["tools"]
    linter = tools.find { |t| t["name"] == "my_linter" }

    assert_equal "db", linter["source"]
    assert_equal "My Linter", linter["display_name"]
    assert_equal "Runs the house linter.", linter["description"]
    assert_nil linter["requires_integration"]
  end

  test "get_agent returns the agent's persona, principles and communication style" do
    agent = create(:agent, scope: @project, name: "release_manager", title: "Release Manager",
                           persona: "You cut releases.", principles: "Ship small.",
                           communication_style: "Terse.", icon: "rocket")

    data = payload(call_tool("get_agent", { project_id: @project.id, agent_id: agent.id }))

    assert_equal "release_manager", data["name"]
    assert_equal "Release Manager", data["title"]
    assert_equal "You cut releases.", data["persona"]
    assert_equal "Ship small.", data["principles"]
    assert_equal "Terse.", data["communication_style"]
    assert_equal "rocket", data["icon"]
    assert_equal "Project", data["scope"]
  end

  test "get_skill returns the full description and SKILL.md content" do
    long_content = "# Formatter\n#{'formatting rule line.' * 60}"
    skill = create(:skill, scope: @project, description: "d" * 400, content: long_content)

    data = payload(call_tool("get_skill", { project_id: @project.id, skill_id: skill.id }))

    assert_equal long_content, data["content"]
    assert_equal skill.description, data["description"]
    assert_equal skill.package, data["package"]
    assert_equal skill.source_url, data["source_url"]
    assert_equal "registry", data["origin"]
  end

  test "get_agent and get_skill never reach another company's records" do
    other = create(:user, :with_company)
    other_project = create(:project, company: other.companies.first, owner: other)
    other_agent = create(:agent, scope: other_project)
    other_skill = create(:skill, scope: other_project)

    assert error?(call_tool("get_agent", { project_id: other_project.id, agent_id: other_agent.id }))
    assert error?(call_tool("get_skill", { project_id: other_project.id, skill_id: other_skill.id }))

    # Nor by pairing a foreign record id with a project the caller can reach.
    body = call_tool("get_agent", { project_id: @project.id, agent_id: other_agent.id })
    assert error?(body)
    assert_match(/not found/i, text(body))

    body = call_tool("get_skill", { project_id: @project.id, skill_id: other_skill.id })
    assert error?(body)
    assert_match(/not found/i, text(body))
  end

  test "list_skills and list_mcp_servers answer for the project" do
    assert_not error?(call_tool("list_skills", { project_id: @project.id }))
    assert_not error?(call_tool("list_mcp_servers", { project_id: @project.id }))
  end

  test "another company's project is not found" do
    other = create(:user, :with_company)
    other_project = create(:project, company: other.companies.first, owner: other)

    body = call_tool("list_integrations", { project_id: other_project.id })
    assert error?(body)
    assert_match(/not found/i, body.dig("result", "content").first["text"])
  end
end
