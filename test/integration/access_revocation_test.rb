# frozen_string_literal: true

require "test_helper"

# Deleting or suspending an account, or revoking a membership, has to take
# effect on everything that outlives a web sign-in: the personal MCP token, a
# running session's MCP key and its credential endpoints, the container gate,
# and the sessions themselves.
class AccessRevocationTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, company: @company, owner: @user)
  end

  def personal_rpc(token)
    post "/mcp",
         params: { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
                    "Authorization" => "Bearer #{token}" }
  end

  def session_rpc(session)
    post "/action_mcp",
         params: { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
                    "X-Session-Key" => session.mcp_key }
  end

  test "a soft-deleted user's personal MCP token stops working and is cleared" do
    token = @user.regenerate_mcp_token!
    personal_rpc(token)
    assert_response :success

    @user.soft_delete!
    personal_rpc(token)

    assert_response :unauthorized
    assert_nil @user.reload.mcp_token_digest
  end

  test "a suspended user's personal MCP token stops working" do
    token = @user.regenerate_mcp_token!

    @user.suspend!
    personal_rpc(token)

    assert_response :unauthorized
  end

  test "revoking a membership shuts the member's running session out and stops it" do
    session = create(:terminal_session, :agent_session, :started, user: @user, project: @project, company: @company)
    session_rpc(session)
    assert_response :success
    SessionService.stubs(:fail_session)

    colleague_admin = create(:user, :admin, company: @company)
    assert colleague_admin
    SessionService.expects(:fail_session).with(has_entry(session: session)).once
    @user.company_memberships.find_by(company: @company).update!(state: "revoked")

    session_rpc(session)
    assert_response :unauthorized
    assert_not session.reload.container_accessible_by?(@user)
  end

  test "a removed member no longer reads their own sessions in that company" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project, company: @company)
    create(:user, :admin, company: @company)
    assert_includes TerminalSession.readable_by(@user), session

    @user.company_memberships.find_by(company: @company).update_columns(state: "revoked")

    assert_not_includes TerminalSession.readable_by(@user.reload), session
  end
end
