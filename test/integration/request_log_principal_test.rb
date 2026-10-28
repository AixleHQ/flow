# frozen_string_literal: true

require "test_helper"

# Production request logs are how an incident is traced back to an account, and
# MCP calls carry no params in them, so the principal has to be on the line itself.
class RequestLogPrincipalTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user, :admin, :onboarding_completed, :with_company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @user.companies.first, owner: @user)
    Bullet.enable = false
  end
  teardown { Bullet.enable = true }

  def logged_payload
    payloads = []
    subscriber = ActiveSupport::Notifications.subscribe("process_action.action_controller") { |*, payload| payloads << payload }
    yield
    payloads.last
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  def mcp_call(headers, body = { method: "tools/list" })
    post "/mcp", params: { jsonrpc: "2.0", id: 1, **body }.to_json,
                 headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream", **headers }
  end

  test "a signed-in page request is logged with its user" do
    sign_in_as(@user)

    payload = logged_payload { get company_projects_path }

    assert_equal @user.id, payload[:user]
  end

  test "a request that never looked up a user is logged without one" do
    payload = logged_payload { get login_path }

    assert_nil payload[:user]
  end

  test "a personal MCP call is logged with the token's user, an agent's with its session" do
    token = @user.regenerate_mcp_token!
    session = create(:terminal_session, :agent_session, :started, user: @user, project: @project)

    personal = logged_payload { mcp_call("Authorization" => "Bearer #{token}") }
    agent = logged_payload { mcp_call("X-Session-Key" => session.mcp_key) }

    assert_equal [ @user.id, nil ], [ personal[:user], personal[:session] ]
    assert_equal [ nil, session.id ], [ agent[:user], agent[:session] ]
  end

  test "an agent's MCP call is logged with its method and the tool it named, and still answered" do
    session = create(:terminal_session, :agent_session, :started, user: @user, project: @project)
    session.tools << Tool.shadow_for(Tools::Registry.fetch("list_sub_steps"))
    key = { "X-Session-Key" => session.mcp_key }

    call = logged_payload { mcp_call(key, method: "tools/call", params: { name: "list_sub_steps", arguments: {} }) }
    answer = response.parsed_body
    list = logged_payload { mcp_call(key) }
    unknown = logged_payload { mcp_call(key, method: "tools/call", params: { name: "no_such_tool" }) }
    forged = logged_payload { mcp_call(key, method: "tools/call", params: { name: "x session=1" }) }

    assert_equal [ "tools/call", "list_sub_steps" ], call.values_at(:rpc, :tool)
    assert_match(/workflow context/i, answer.dig("result", "content").pluck("text").join("\n"))
    assert_equal [ "tools/list", nil ], list.values_at(:rpc, :tool)
    assert_equal [ "tools/call", "no_such_tool" ], unknown.values_at(:rpc, :tool)
    assert_equal [ "tools/call", nil ], forged.values_at(:rpc, :tool)
  end

  test "an MCP request whose body is not JSON is answered as before and logs no method" do
    session = create(:terminal_session, :agent_session, :started, user: @user, project: @project)

    payload = logged_payload do
      post "/mcp", params: "{not json",
                   headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
                              "X-Session-Key" => session.mcp_key }
    end

    assert_equal session.id, payload[:session]
    assert_nil payload[:rpc]
    assert_equal(-32700, response.parsed_body.dig("error", "code"))
  end
end
