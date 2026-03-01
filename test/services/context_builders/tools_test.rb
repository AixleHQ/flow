# frozen_string_literal: true

require "test_helper"

class ContextBuilders::ToolsTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive")
  end

  test "shell-tools section is always produced" do
    @session.stubs(:available_tools).returns([])
    builder = ContextBuilders::Tools.new(@session)
    sections = builder.build

    shell = sections.find { |s| s.tag == "shell-tools" }
    assert_not_nil shell
    assert_equal :info, shell.priority
    assert_includes shell.content, "ripgrep"
  end

  test "mcp-servers section produced when MCP servers exist" do
    builder = ContextBuilders::Tools.new(@session)
    sections = builder.build

    mcp = sections.find { |s| s.tag == "mcp-servers" }
    assert_not_nil mcp
    assert_includes mcp.content, "palad-tools"
  end

  test "custom-tools section not produced when no available tools" do
    @session.stubs(:available_tools).returns([])
    builder = ContextBuilders::Tools.new(@session)
    sections = builder.build

    custom = sections.find { |s| s.tag == "custom-tools" }
    assert_nil custom
  end
end
