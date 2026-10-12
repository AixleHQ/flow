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
    assert_includes mcp.content, "aixle-tools"
  end

  test "custom-tools section not produced when no available tools" do
    @session.stubs(:available_tools).returns([])
    builder = ContextBuilders::Tools.new(@session)
    sections = builder.build

    custom = sections.find { |s| s.tag == "custom-tools" }
    assert_nil custom
  end

  test "custom-tools names each tool without repeating its description" do
    @session.stubs(:available_tools).returns([
      build(:tool, :workflow, name: "board_move_task", description: "Move a task to another board column"),
      build(:tool, :workflow, name: "board_add_comment", description: "Add an agent comment to a task")
    ])
    content = ContextBuilders::Tools.new(@session).build.find { |s| s.tag == "custom-tools" }.content

    assert_includes content, "`board_move_task`, `board_add_comment`"
    assert_not_includes content, "Move a task to another board column"
    assert_not_includes content, "Tool Execution Modes"
  end

  test "custom-tools explains the asynchronous mode only when a container tool is present" do
    @session.stubs(:available_tools).returns([
      build(:tool, :workflow, name: "board_move_task"),
      build(:tool, name: "security_scan", execution_mode: "container")
    ])
    content = ContextBuilders::Tools.new(@session).build.find { |s| s.tag == "custom-tools" }.content

    assert_includes content, "Tool Execution Modes"
    assert_includes content, "Container tools: `security_scan`"
    assert_not_includes content, "`board_move_task`, `security_scan`"
  end
end
