# frozen_string_literal: true

require "test_helper"

class TerminalSessionTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
  end

  # == session_config validation ==

  test "valid with empty session_config" do
    session = build(:terminal_session, user: @user, session_config: {})
    assert session.valid?
  end

  test "valid with allowed session_config keys" do
    session = build(:terminal_session, user: @user, session_config: {
      "config_files" => { "CLAUDE.md" => "# Context" },
      "env_vars" => { "NODE_ENV" => "production" },
      "mcp_server_ids" => [ 1, 2 ],
      "tool_ids" => [ 3, 7 ],
      "agent_id" => 42
    })
    assert session.valid?
  end

  test "invalid with unknown session_config keys" do
    session = build(:terminal_session, user: @user, session_config: {
      "config_files" => {},
      "unknown_key" => "value"
    })
    assert_not session.valid?
    assert_includes session.errors[:session_config].join, "unknown keys"
  end

  # == session_config accessors ==

  test "config_files returns config_files hash" do
    session = build(:terminal_session, user: @user, session_config: {
      "config_files" => { "CLAUDE.md" => "# Context" }
    })
    assert_equal({ "CLAUDE.md" => "# Context" }, session.config_files)
  end

  test "config_files returns empty hash when absent" do
    session = build(:terminal_session, user: @user, session_config: {})
    assert_equal({}, session.config_files)
  end

  test "env_vars returns env_vars hash" do
    session = build(:terminal_session, user: @user, session_config: {
      "env_vars" => { "KEY" => "value" }
    })
    assert_equal({ "KEY" => "value" }, session.env_vars)
  end

  test "env_vars returns empty hash when absent" do
    session = build(:terminal_session, user: @user, session_config: {})
    assert_equal({}, session.env_vars)
  end

  test "mcp_server_ids returns array" do
    session = build(:terminal_session, user: @user, session_config: {
      "mcp_server_ids" => [ 1, 5, 12 ]
    })
    assert_equal [ 1, 5, 12 ], session.mcp_server_ids
  end

  test "mcp_server_ids returns empty array when absent" do
    session = build(:terminal_session, user: @user, session_config: {})
    assert_equal [], session.mcp_server_ids
  end

  test "tool_ids returns array" do
    session = build(:terminal_session, user: @user, session_config: {
      "tool_ids" => [ 3, 7, 14 ]
    })
    assert_equal [ 3, 7, 14 ], session.tool_ids
  end

  test "tool_ids returns empty array when absent" do
    session = build(:terminal_session, user: @user, session_config: {})
    assert_equal [], session.tool_ids
  end

  test "configured_agent_id returns agent_id" do
    session = build(:terminal_session, user: @user, session_config: {
      "agent_id" => 42
    })
    assert_equal 42, session.configured_agent_id
  end

  test "configured_agent_id returns nil when absent" do
    session = build(:terminal_session, user: @user, session_config: {})
    assert_nil session.configured_agent_id
  end

  # == available_tools via session_config tool_ids ==

  test "available_tools returns tools from tool_ids" do
    tool1 = create(:tool, scope: @company)
    tool2 = create(:tool, scope: @company)

    session = create(:terminal_session, user: @user, project: @project, session_config: {
      "tool_ids" => [ tool1.id, tool2.id ]
    })

    assert_includes session.available_tools, tool1
    assert_includes session.available_tools, tool2
  end

  test "available_tools falls back to project tools when no tool_ids" do
    tool = create(:tool, scope: @project)
    session = create(:terminal_session, user: @user, project: @project, session_config: {})

    assert_includes session.available_tools, tool
  end

  test "available_tools returns empty when no project and no tool_ids" do
    session = build(:terminal_session, user: @user, project: nil, session_config: {})

    assert_empty session.available_tools
  end

  test "available_tools ignores non-existent tool_ids" do
    tool = create(:tool, scope: @company)

    session = create(:terminal_session, user: @user, project: @project, session_config: {
      "tool_ids" => [ tool.id, 999_999 ]
    })

    assert_equal 1, session.available_tools.count
    assert_includes session.available_tools, tool
  end

  # == backwards compatibility ==

  test "auth_setup sessions work with empty session_config" do
    session = create(:terminal_session, :auth_setup, user: @user, session_config: {})

    assert session.persisted?
    assert_equal({}, session.session_config)
    assert_equal({}, session.config_files)
    assert_equal({}, session.env_vars)
    assert_equal([], session.mcp_server_ids)
    assert_equal([], session.tool_ids)
    assert_nil session.configured_agent_id
  end
end
