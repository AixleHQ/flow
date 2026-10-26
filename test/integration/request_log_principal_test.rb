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

  def mcp_call(headers)
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
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
end
