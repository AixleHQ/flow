# frozen_string_literal: true

require "test_helper"

class TerminalSessionMCPTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
  end

  test "generates mcp_key on create" do
    session = TerminalSession.create!(
      session_type: "agent_session",
      agent_type: "claude_code",
      state: "not_started",
      user: @user,
      project: @project
    )

    assert_not_nil session.mcp_key
    assert session.mcp_key.length > 20
  end

  test "mcp_key is unique" do
    session1 = create(:terminal_session, user: @user, project: @project)
    session2 = create(:terminal_session, user: @user, project: @project)

    assert_not_equal session1.mcp_key, session2.mcp_key
  end

  test "active? returns true for active states" do
    %w[not_started running ready].each do |state|
      session = build(:terminal_session, state: state, user: @user)
      assert session.active?, "Expected #{state} to be active"
    end
  end

  test "active? returns false for inactive states" do
    %w[finishing finished failed].each do |state|
      session = build(:terminal_session, state: state, user: @user)
      assert_not session.active?, "Expected #{state} to be inactive"
    end
  end

  test "available_tools returns tools from HABTM association" do
    tool = create(:tool, scope: @company)
    session = create(:terminal_session, user: @user, project: @project)
    session.tools << tool

    assert_includes session.available_tools, tool
  end

  test "available_tools returns project tools when no tool_ids" do
    tool = create(:tool, scope: @project)
    session = create(:terminal_session, user: @user, project: @project)

    assert_includes session.available_tools, tool
  end

  test "available_tools returns empty when no project and no tool_ids" do
    session = build(:terminal_session, user: @user, project: nil)

    assert_empty session.available_tools
  end
end
