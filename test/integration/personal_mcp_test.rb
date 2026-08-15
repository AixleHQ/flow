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

  # One request of the stateless "modern" lifecycle (2026-07-28, SEP-2575) —
  # the one Claude Code speaks: no `initialize`, no session id, the protocol
  # version and client capabilities carried in a per-request `_meta` envelope
  # and mirrored in routing headers.
  def modern_rpc(method, params = {}, name: nil, version: MCP::Configuration::LATEST_MODERN_PROTOCOL_VERSION)
    envelope = {
      "io.modelcontextprotocol/protocolVersion" => version,
      "io.modelcontextprotocol/clientCapabilities" => {},
      "io.modelcontextprotocol/clientInfo" => { name: "claude-code", version: "1" }
    }
    post "/mcp",
         params: { jsonrpc: "2.0", id: 1, method: method, params: params.merge(_meta: envelope) }.to_json,
         headers: { "Content-Type" => "application/json",
                    "Accept" => "application/json, text/event-stream",
                    "Authorization" => "Bearer #{@token}",
                    "MCP-Protocol-Version" => version,
                    "Mcp-Method" => method,
                    "Mcp-Name" => name }.compact
    response.parsed_body
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

  # ── the legacy `initialize` handshake ──

  test "a modern offer is counter-offered the newest handshake version" do
    # The modern lifecycle has no handshake, so `initialize` must never agree
    # to 2026-07-28 — the version Claude Code always offers. Echoing it back
    # promised result shapes the handshake era does not emit, and the client
    # discarded every list response and registered no tools at all.
    assert_equal MCP::Configuration::LATEST_HANDSHAKE_PROTOCOL_VERSION, initialize_with("2026-07-28")
  end

  test "an offer the handshake serves is agreed to unchanged" do
    MCP::Configuration::SUPPORTED_HANDSHAKE_PROTOCOL_VERSIONS.each do |version|
      assert_equal version, initialize_with(version)
    end
  end

  test "an unrecognized offer is counter-offered the newest handshake version" do
    assert_equal MCP::Configuration::LATEST_HANDSHAKE_PROTOCOL_VERSION, initialize_with("not-a-version")
  end

  test "an offer that is not a string still gets the spec's invalid-params error" do
    error = rpc("initialize", { protocolVersion: 20260728, capabilities: {},
                                clientInfo: { name: "test-client", version: "1" } })["error"]

    assert_equal(-32602, error["code"])
  end

  test "the handshake list responses match the negotiated version" do
    negotiated = initialize_with("2026-07-28")

    # The client sends the negotiated version back on every subsequent request:
    # it has to be accepted, and the results have to be valid for it — which
    # on a handshake version means neither `resultType` nor the cache hints,
    # fields a pre-2026 client does not know.
    { "tools/list" => "tools", "prompts/list" => "prompts", "resources/list" => "resources" }
      .each do |method, key|
      result = rpc(method, {}, protocol_version: negotiated)["result"]

      assert_response :success
      assert_not_empty result[key]
      assert_nil result["resultType"]
      assert_nil result["ttlMs"]
      assert_nil result["cacheScope"]
    end
  end

  # ── the modern (SEP-2575) lifecycle ──

  test "the modern list responses carry the resultType and cache hints their schema requires" do
    # The actual Claude Code failure: it never negotiates through
    # `initialize`, it sends the per-request envelope, and 2026-07-28 makes
    # `resultType` (SEP-2322) required on every result and `ttlMs`/`cacheScope`
    # (SEP-2549) required on the cacheable ones. Unstamped, every list response
    # failed the client's schema check and the server exposed 0 tools.
    { "tools/list" => "tools", "prompts/list" => "prompts", "resources/list" => "resources" }
      .each do |method, key|
      result = modern_rpc(method)["result"]

      assert_response :success
      assert_not_empty result[key], "#{method} served nothing"
      assert_equal "complete", result["resultType"], "#{method} is missing resultType"
      assert_equal 0, result["ttlMs"], "#{method} is missing the ttlMs cache hint"
      assert_equal "private", result["cacheScope"], "#{method} is missing the cacheScope cache hint"
    end
  end

  test "a modern tools/call is dispatched and its result is stamped" do
    result = modern_rpc("tools/call", { name: "list_companies", arguments: {} },
                        name: "list_companies")["result"]

    assert_response :success
    assert_equal "complete", result["resultType"]
    companies = JSON.parse(result["content"].first["text"])["companies"]
    assert_equal [ @company.id ], companies.map { |c| c["id"] }
  end

  test "a modern request for a version the server does not serve is refused with -32022" do
    error = modern_rpc("tools/list", version: "2099-01-01")["error"]

    assert_equal(-32022, error["code"])
    assert_equal MCP::Configuration::SUPPORTED_MODERN_PROTOCOL_VERSIONS, error.dig("data", "supported")
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
