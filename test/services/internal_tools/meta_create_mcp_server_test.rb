# frozen_string_literal: true

require "test_helper"

class InternalTools::MetaCreateMCPServerTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, :agent_session, user: @user, project: @project)
  end

  def run_tool(params)
    InternalTools::MetaCreateMCPServer.new(params: params, session: @session).execute
  end

  # ── default (Project) scope ──

  test "creates a project-scoped custom MCP server by default" do
    result = nil
    assert_difference -> { MCPServer.count }, 1 do
      result = run_tool(name: "tavily", url: "https://mcp.example.com/v1")
    end

    assert_equal 0, result[:exit_code]
    assert_equal "", result[:stderr]

    data = JSON.parse(result[:stdout])
    mcp = MCPServer.find(data["id"])
    assert mcp.valid?, mcp.errors.full_messages.to_sentence

    # Returned payload mirrors the persisted record
    assert_equal mcp.name, data["name"]

    # Persisted state: defaults applied, scoped to the session's project
    assert_equal @project, mcp.scope
    assert_equal "tavily", mcp.name
    assert mcp.custom?
    assert_equal "http", mcp.transport.to_s # default transport
    assert mcp.enabled?
    assert_equal({}, mcp.headers)
    assert_equal({}, mcp.env)
  end

  # ── explicit Project scope ──

  test "creates a project-scoped server when scope_type is Project with scope_id" do
    result = run_tool(
      name: "context7",
      url: "https://mcp.example.com/context7",
      scope_type: "Project",
      scope_id: @project.id
    )

    assert_equal 0, result[:exit_code]
    mcp = MCPServer.find(JSON.parse(result[:stdout])["id"])
    assert_equal @project, mcp.scope
    assert mcp.custom?
  end

  test "infers Project scope_id from session context when omitted" do
    result = run_tool(
      name: "inferred-project-server",
      url: "https://mcp.example.com/inferred",
      scope_type: "Project"
    )

    assert_equal 0, result[:exit_code]
    mcp = MCPServer.find(JSON.parse(result[:stdout])["id"])
    assert_equal @project, mcp.scope
  end

  # ── stdio transport ──

  test "creates a stdio-transport server with a command and no url" do
    result = run_tool(
      name: "playwright",
      transport: "stdio",
      command: "npx @playwright/mcp --headless",
      scope_type: "Project"
    )

    assert_equal 0, result[:exit_code]
    mcp = MCPServer.find(JSON.parse(result[:stdout])["id"])
    assert mcp.valid?, mcp.errors.full_messages.to_sentence
    assert_equal "stdio", mcp.transport.to_s
    assert_nil mcp.url
    # The tool takes one line, like the install form; the model stores it split.
    assert_equal "npx", mcp.command
    assert_equal %w[@playwright/mcp --headless], mcp.args
    assert_equal "npx @playwright/mcp --headless", mcp.command_line
  end

  # ── explicit attributes; name is stored verbatim ──

  test "persists the name verbatim plus description, headers, and env" do
    result = run_tool(
      name: "Tavily Search",
      url: "https://mcp.example.com/v1",
      description: "Web search via Tavily",
      headers: { "Authorization" => "Bearer secret" },
      env: { "TAVILY_API_KEY" => "abc123" },
      scope_type: "Project"
    )

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    mcp = MCPServer.find(data["id"])

    # Name is kept as typed; the lowercase protocol key is derived at config time.
    assert_equal "Tavily Search", mcp.name
    assert_equal "tavily_search", mcp.config_key
    assert_equal "Web search via Tavily", mcp.description
    assert_equal({ "Authorization" => "Bearer secret" }, mcp.headers)
    assert_equal({ "TAVILY_API_KEY" => "abc123" }, mcp.env)
  end

  # ── side effect: builder activity persisted to session metadata ──

  test "records a created_mcp_server builder activity on the session" do
    result = run_tool(name: "activity-server", url: "https://mcp.example.com/v1")

    assert_equal 0, result[:exit_code]
    mcp = MCPServer.find(JSON.parse(result[:stdout])["id"])

    activities = @session.reload.metadata["builder_activities"]
    assert_not_nil activities
    activity = activities.last
    assert_equal "created_mcp_server", activity["action"]
    assert_equal "MCPServer", activity["entity_type"]
    assert_equal mcp.id, activity["entity_id"]
    assert_equal mcp.name, activity["entity_name"]
  end
end
