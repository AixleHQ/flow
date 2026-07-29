# frozen_string_literal: true

require "test_helper"

# Wire contract of the MCP endpoint after the swap to the official mcp gem:
# same paths (/action_mcp alias + /mcp), same auth (X-Session-Key = mcp_key),
# same availability semantics (hide in tools/list; actionable in-band error
# for entitled-but-disconnected on tools/call; opaque error otherwise).
class McpControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, :agent_session, :started, user: @user, project: @project)
  end

  def rpc(method, params = {}, key: @session.mcp_key, path: "/action_mcp")
    post path,
         params: { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json,
         headers: { "Content-Type" => "application/json",
                    "Accept" => "application/json, text/event-stream",
                    "X-Session-Key" => key }.compact
    response.parsed_body
  end

  def attach_platform_tool(name)
    Tool.shadow_for(Tools::Registry.fetch(name)).tap { |row| @session.tools << row }
  end

  def listed_tools(body)
    body.dig("result", "tools")
  end

  # ── auth ──

  test "rejects requests without a valid session key" do
    rpc("tools/list", key: nil)
    assert_response :unauthorized

    rpc("tools/list", key: "wrong")
    assert_response :unauthorized
  end

  test "accepts the key as a bearer token" do
    post "/action_mcp",
         params: { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }.to_json,
         headers: { "Content-Type" => "application/json",
                    "Accept" => "application/json, text/event-stream",
                    "Authorization" => "Bearer #{@session.mcp_key}" }
    assert_response :success
  end

  test "initialize negotiates and reports the server" do
    body = rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "t", version: "1" } })

    assert_response :success
    assert_equal "aixle-tools", body.dig("result", "serverInfo", "name")
  end

  # ── tools/list ──

  test "tools/list serves available tools sorted with tags in _meta" do
    attach_platform_tool("mark_sub_step")
    attach_platform_tool("board_list_tasks")

    tools = listed_tools(rpc("tools/list"))

    names = tools.map { |t| t["name"] }
    assert_equal names.sort, names
    assert_includes names, "board_list_tasks"
    board = tools.find { |t| t["name"] == "board_list_tasks" }
    assert_equal [ "board" ], board.dig("_meta", "ai.aixle/tags")
    assert_equal "object", board.dig("inputSchema", "type")
  end

  test "tools/list hides an integration-gated tool until the integration is active" do
    attach_platform_tool("slack_post_message")
    attach_platform_tool("board_list_tasks")

    names = listed_tools(rpc("tools/list")).map { |t| t["name"] }
    refute_includes names, "slack_post_message"

    create(:integration, company: @company, project: @project, provider: :slack,
                         status: :active, connected_by: @user)
    names = listed_tools(rpc("tools/list")).map { |t| t["name"] }
    assert_includes names, "slack_post_message"
  end

  test "tools/list serializes from the definition even when the shadow row is stale" do
    row = attach_platform_tool("read_tool_result")
    row.update_columns(description: "STALE", input_schema: { "type" => "object" })

    serialized = listed_tools(rpc("tools/list")).find { |t| t["name"] == "read_tool_result" }
    definition = Tools::Registry.fetch("read_tool_result")

    assert_equal definition.description, serialized["description"]
    assert_equal definition.input_schema["properties"].keys,
                 serialized.dig("inputSchema", "properties").keys
  end

  # ── tools/call ──

  test "tools/call executes an available tool" do
    attach_platform_tool("list_sub_steps")

    body = rpc("tools/call", { name: "list_sub_steps", arguments: {} })

    text = body.dig("result", "content").map { |c| c["text"] }.join("\n")
    # Reaches the handler, which demands workflow context — proof of dispatch.
    assert_match(/workflow context/i, text)
  end

  test "tools/call on an entitled-but-disconnected tool returns an actionable in-band error" do
    attach_platform_tool("slack_post_message")

    body = rpc("tools/call", { name: "slack_post_message", arguments: { text: "hi" } })

    assert body.dig("result", "isError")
    text = body.dig("result", "content").map { |c| c["text"] }.join("\n")
    assert_match(/slack integration is not connected/i, text)
    assert_match(/Project Settings/, text)
  end

  test "tools/call outside the entitlement stays an opaque protocol error" do
    body = rpc("tools/call", { name: "slack_post_message", arguments: {} })

    assert_nil body["result"]
    assert body["error"].present?
    refute_match(/Project Settings/, body["error"]["message"].to_s)
  end

  test "the /mcp alias serves the same endpoint" do
    attach_platform_tool("board_list_tasks")

    names = listed_tools(rpc("tools/list", path: "/mcp")).map { |t| t["name"] }
    assert_includes names, "board_list_tasks"
  end

  test "a tampered custom tool is hidden from serving (digest fail-closed)" do
    tool = create(:tool, scope: @project, name: "my_linter", docker_image: "l:1")
    @session.tools << tool

    names = listed_tools(rpc("tools/list")).map { |t| t["name"] }
    assert_includes names, "my_linter"

    tool.update_columns(description: "tampered past validations")
    names = listed_tools(rpc("tools/list")).map { |t| t["name"] }
    refute_includes names, "my_linter"
  end

  # ── integration-gated Coder tools ──

  test "Coder tools surface through aixle-tools once the Coder integration is active" do
    names = listed_tools(rpc("tools/list")).map { |t| t["name"] }
    refute_includes names, "coder_ssh_exec"

    create(:integration, company: @company, project: @project,
                         provider: :coder, status: :active, connected_by: @user)

    names = listed_tools(rpc("tools/list")).map { |t| t["name"] }
    assert_includes names, "coder_ssh_exec"
  end
end
