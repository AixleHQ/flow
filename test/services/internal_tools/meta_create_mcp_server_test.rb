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

  # ── default (Company) scope ──

  test "creates a company-scoped custom MCP server by default" do
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
    assert_equal mcp.display_name, data["display_name"]

    # Persisted state: defaults applied, scoped to the session's company
    assert_equal @company, mcp.scope
    assert_equal "tavily", mcp.name
    assert_equal "Tavily", mcp.display_name # titleized from name
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
      scope_type: "Company"
    )

    assert_equal 0, result[:exit_code]
    mcp = MCPServer.find(JSON.parse(result[:stdout])["id"])
    assert mcp.valid?, mcp.errors.full_messages.to_sentence
    assert_equal "stdio", mcp.transport.to_s
    assert_equal "npx @playwright/mcp --headless", mcp.command
    assert_nil mcp.url
    assert_equal %w[npx @playwright/mcp --headless], mcp.parsed_command
  end

  # ── explicit attributes + name sanitization ──

  test "persists explicit display_name, description, headers, env, and sanitizes the name" do
    result = run_tool(
      name: "Tavily Search",
      url: "https://mcp.example.com/v1",
      display_name: "Tavily Web Search",
      description: "Web search via Tavily",
      headers: { "Authorization" => "Bearer secret" },
      env: { "TAVILY_API_KEY" => "abc123" },
      scope_type: "Company"
    )

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    mcp = MCPServer.find(data["id"])

    assert_equal "tavily-search", mcp.name # downcased + non-slug chars replaced
    assert_equal "Tavily Web Search", mcp.display_name
    assert_equal "Tavily Web Search", data["display_name"]
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
    assert_equal mcp.display_name, activity["entity_name"]
  end
end
