# frozen_string_literal: true

require "test_helper"

# The personal (session-less) MCP server: one amcp_ token per user on the
# same /mcp endpoint, serving audience-:user registry tools with the user's
# own access level.
class PersonalMCPTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, company: @company, owner: @user)
    @token = @user.regenerate_mcp_token!
  end

  def rpc(method, params = {}, token: @token, protocol_version: nil)
    post "/mcp",
         params: { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json,
         headers: { "Content-Type" => "application/json",
                    "Accept" => "application/json, text/event-stream",
                    "Authorization" => "Bearer #{token}",
                    "MCP-Protocol-Version" => protocol_version }.compact
    response.parsed_body
  end

  def initialize_with(version)
    rpc("initialize", { protocolVersion: version, capabilities: {},
                        clientInfo: { name: "test-client", version: "1" } }).dig("result", "protocolVersion")
  end

  def prompt_text(name)
    rpc("prompts/get", { name: name, arguments: {} }).dig("result", "messages").first.dig("content", "text")
  end

  test "token lifecycle: regenerate rotates, disable revokes" do
    old_token = @token
    new_token = @user.regenerate_mcp_token!

    rpc("tools/list", token: old_token)
    assert_response :unauthorized

    rpc("tools/list", token: new_token)
    assert_response :success

    @user.disable_mcp_token!
    rpc("tools/list", token: new_token)
    assert_response :unauthorized
  end

  test "tools/list serves the user-audience registry tools" do
    names = rpc("tools/list").dig("result", "tools").map { |t| t["name"] }

    assert_includes names, "list_companies"
    assert_includes names, "list_projects"
    # Session-audience tools never leak into the personal server.
    refute_includes names, "board_list_tasks"
    refute_includes names, "meta_create_tool"
  end

  test "personal tools are not materialized as shadow rows and stay out of session serving" do
    Tools::Reconciler.run!

    assert_not Tool.exists?(name: "list_companies")
    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    assert_empty session.available_tools.map(&:name) & %w[list_companies list_projects]
  end

  test "list_companies and list_projects answer with the user's own scope" do
    other = create(:user, :with_company)
    create(:project, company: other.companies.first, owner: other)

    body = rpc("tools/call", { name: "list_companies", arguments: {} })
    companies = JSON.parse(body.dig("result", "content").first["text"])["companies"]
    assert_equal [ @company.id ], companies.map { |c| c["id"] }

    body = rpc("tools/call", { name: "list_projects", arguments: {} })
    projects = JSON.parse(body.dig("result", "content").first["text"])["projects"]
    assert_equal [ @project.id ], projects.map { |p| p["id"] }
  end

  test "the guidance prompts are served" do
    names = rpc("prompts/list").dig("result", "prompts").map { |p| p["name"] }
    assert_equal %w[author_step build_workflow setup_project tool_catalog], names.sort

    wf = prompt_text("build_workflow")
    assert_match(/create_workflow/, wf)
    assert_match(/trigger_workflow/, wf)

    step = prompt_text("author_step")
    assert_match(/instructions/i, step)
    assert_match(/depends_on_step_ids/, step)

    setup = prompt_text("setup_project")
    assert_match(/create_project/, setup)
    # The from-scratch path only works because the board can be created here.
    assert_match(/setup_board/, setup)
    assert_match(/get_integration_setup_url/, setup)

    catalog = prompt_text("tool_catalog")
    served = rpc("tools/list").dig("result", "tools").map { |t| t["name"] }
    missing = served.reject { |name| catalog.include?("`#{name}`") }
    assert_empty missing, "tool catalog prompt is missing: #{missing.join(', ')}"
  end

  test "the server introduces itself with instructions on initialize" do
    result = rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {},
                                 clientInfo: { name: "test-client", version: "1" } })["result"]

    assert_match(/project_id/, result["instructions"])
    assert_match(/list_companies/, result["instructions"])
    assert_match(/setup_project/, result["instructions"])
  end

  # ── protocol version negotiation ──

  test "an offer newer than what the server serves negotiates down" do
    # Claude Code always offers 2026-07-28, whose results all require a
    # `resultType` this server does not emit; agreeing to it made the client
    # discard every list response and register no tools at all.
    assert_equal Tools::MCPProtocol::MAX_NEGOTIABLE_VERSION, initialize_with("2026-07-28")
  end

  test "an offer the server serves is agreed to unchanged" do
    Tools::MCPProtocol::NEGOTIABLE_VERSIONS.each do |version|
      assert_equal version, initialize_with(version)
    end
  end

  test "an unrecognized offer negotiates the newest version the server serves" do
    assert_equal Tools::MCPProtocol::MAX_NEGOTIABLE_VERSION, initialize_with("not-a-version")
  end

  test "the list responses match the negotiated version" do
    negotiated = initialize_with("2026-07-28")

    # The client sends the negotiated version back on every subsequent request:
    # it has to be accepted, and the results have to be valid for it — which
    # for 2025-11-25 means no `resultType` is expected.
    { "tools/list" => "tools", "prompts/list" => "prompts", "resources/list" => "resources" }
      .each do |method, key|
      result = rpc(method, {}, protocol_version: negotiated)["result"]

      assert_response :success
      assert_not_empty result[key]
      assert_nil result["resultType"]
    end
  end

  test "the platform reference is served as a resource" do
    listed = rpc("resources/list").dig("result", "resources")
    assert_equal [ "aixle://reference/system" ], listed.map { |r| r["uri"] }

    contents = rpc("resources/read", { uri: "aixle://reference/system" }).dig("result", "contents").first
    assert_equal "text/markdown", contents["mimeType"]
    assert_match(/Aixle Platform/, contents["text"])
  end

  test "the last-used timestamp is touched on requests" do
    assert_nil @user.mcp_token_last_used_at

    rpc("tools/list")

    assert_not_nil @user.reload.mcp_token_last_used_at
  end
end
