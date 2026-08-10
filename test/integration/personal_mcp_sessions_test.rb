# frozen_string_literal: true

require "test_helper"

# End-to-end over the personal MCP server: the session tools are discoverable,
# reach their handlers with a user context, and answer in-band.
class PersonalMCPSessionsTest < ActionDispatch::IntegrationTest
  setup do
    @runtime = stub_container_runtime
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, company: @company, owner: @user)
    @token = @user.regenerate_mcp_token!
  end

  teardown { cleanup_runtime_overrides }

  def call_tool(name, args = {})
    post "/mcp",
         params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                   params: { name: name, arguments: args } }.to_json,
         headers: { "Content-Type" => "application/json",
                    "Accept" => "application/json, text/event-stream",
                    "Authorization" => "Bearer #{@token}" }
    response.parsed_body
  end

  def payload(body) = JSON.parse(body.dig("result", "content").first["text"])
  def tool_error?(body) = body.dig("result", "isError")
  def text(body) = body.dig("result", "content").map { |c| c["text"] }.join(" ")

  test "the session tools are served to a personal token" do
    post "/mcp",
         params: { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }.to_json,
         headers: { "Content-Type" => "application/json",
                    "Accept" => "application/json, text/event-stream",
                    "Authorization" => "Bearer #{@token}" }

    served = response.parsed_body.dig("result", "tools").map { |t| t["name"] }
    assert_includes served, "list_sessions"
    assert_includes served, "get_session_log"
    assert_includes served, "stop_session"
    assert_includes served, "trigger_task_workflow"
  end

  test "list_sessions then get_session_log reads the running container" do
    session = create(:terminal_session, :agent_session, :running, user: @user, project: @project)
    @runtime.set_terminal_pane("waiting for the build\n", last_output_at: 30.seconds.ago)

    listed = payload(call_tool("list_sessions", { project_id: @project.id }))
    assert_equal [ session.id ], listed["sessions"].map { |s| s["id"] }

    body = payload(call_tool("get_session_log", { session_id: session.id, lines: 10 }))
    assert_equal "live", body["source"]
    assert_match(/waiting for the build/, body["log"])
    assert_operator body["idle_seconds"], :>=, 0
  end

  test "stop_session finishes a session; another user's is not found" do
    session = create(:terminal_session, :agent_session, :running, user: @user, project: @project)

    assert_not tool_error?(call_tool("stop_session", { session_id: session.id }))
    assert_equal "finished", session.reload.state

    stranger = create(:user, :with_company)
    theirs = create(:terminal_session, :agent_session, :running, user: stranger,
                    project: create(:project, owner: stranger, company: stranger.companies.first))

    denied = call_tool("stop_session", { session_id: theirs.id })
    assert tool_error?(denied)
    assert_match(/not found/i, text(denied))
  end
end
