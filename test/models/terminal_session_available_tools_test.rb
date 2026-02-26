# frozen_string_literal: true

require "test_helper"

class TerminalSessionAvailableToolsTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)

    @workflow_tool1 = create(:tool, :workflow, name: "list_sub_steps",
      display_name: "List Sub-Steps")
    @workflow_tool2 = create(:tool, :workflow, name: "mark_sub_step",
      display_name: "Mark Sub-Step")
    @workflow_tool3 = create(:tool, :workflow, name: "write_step_note",
      display_name: "Write Step Note")
    @system_tool = create(:tool, :system, name: "static_analyzer",
      display_name: "Static Analyzer", docker_image: "analyzer:latest",
      execution_mode: :container)
    @read_tool_result = create(:tool, :internal, name: "read_tool_result",
      display_name: "Read Tool Result")
  end

  # == Workflow tools: auto-injected for workflow_step sessions ==

  test "workflow tools are included for workflow_step sessions" do
    session = create(:terminal_session, user: @user, project: @project,
      session_type: "workflow_step", agent_type: nil)

    names = session.available_tools.map(&:name)

    assert_includes names, "list_sub_steps"
    assert_includes names, "mark_sub_step"
    assert_includes names, "write_step_note"
  end

  test "workflow tools are NOT included for agent_session" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project)

    names = session.available_tools.map(&:name)

    refute_includes names, "list_sub_steps"
    refute_includes names, "mark_sub_step"
    refute_includes names, "write_step_note"
  end

  test "workflow tools are NOT included for auth_setup" do
    session = create(:terminal_session, :auth_setup, user: @user, project: nil)

    names = session.available_tools.map(&:name)

    refute_includes names, "list_sub_steps"
    refute_includes names, "mark_sub_step"
  end

  # == System tools: explicitly attached ==

  test "system tool is NOT included unless explicitly selected" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project)

    names = session.available_tools.map(&:name)

    refute_includes names, "static_analyzer"
  end

  test "system tool is included when explicitly added to session tools" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    session.tools << @system_tool

    names = session.available_tools.map(&:name)

    assert_includes names, "static_analyzer"
  end

  # == Internal tools: auto-injected when container tools present ==

  test "internal tools are auto-injected when container tool is attached" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    session.tools << @system_tool

    names = session.available_tools.map(&:name)

    assert_includes names, "read_tool_result"
  end

  test "internal tools are NOT present when no container tools attached" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project)

    names = session.available_tools.map(&:name)

    refute_includes names, "read_tool_result"
  end

  test "internal tools are auto-injected when custom container tool is attached" do
    custom_tool = create(:tool, scope: @company, name: "my_linter",
      display_name: "My Linter", docker_image: "linter:1.0")

    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    session.tools << custom_tool

    names = session.available_tools.map(&:name)

    assert_includes names, "read_tool_result"
  end

  test "internal tools are auto-injected when project has custom container tools (fallback)" do
    create(:tool, scope: @project, name: "project_tool",
      display_name: "Project Tool", docker_image: "pt:1.0")

    session = create(:terminal_session, :agent_session, user: @user, project: @project)

    names = session.available_tools.map(&:name)

    assert_includes names, "project_tool"
    assert_includes names, "read_tool_result"
  end

  # == Custom tools ==

  test "custom tools from session.tools are included" do
    custom_tool = create(:tool, scope: @company, name: "my_linter",
      display_name: "My Linter", docker_image: "linter:1.0")

    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    session.tools << custom_tool

    names = session.available_tools.map(&:name)

    assert_includes names, "my_linter"
  end

  test "falls back to project custom tools when no custom tools explicitly selected" do
    project_tool = create(:tool, scope: @project, name: "project_tool",
      display_name: "Project Tool", docker_image: "pt:1.0")

    session = create(:terminal_session, :agent_session, user: @user, project: @project)

    names = session.available_tools.map(&:name)

    assert_includes names, "project_tool"
  end

  test "does not fall back to project tools when custom tools are explicitly selected" do
    create(:tool, scope: @project, name: "project_tool",
      display_name: "Project Tool", docker_image: "pt:1.0")
    custom_tool = create(:tool, scope: @company, name: "my_tool",
      display_name: "My Tool", docker_image: "mt:1.0")

    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    session.tools << custom_tool

    names = session.available_tools.map(&:name)

    assert_includes names, "my_tool"
    refute_includes names, "project_tool"
  end

  # == Workflow step with mixed tools ==

  test "workflow_step session gets workflow tools and explicitly selected tools" do
    session = create(:terminal_session, user: @user, project: @project,
      session_type: "workflow_step", agent_type: nil)
    session.tools << @system_tool

    names = session.available_tools.map(&:name)

    assert_includes names, "list_sub_steps"
    assert_includes names, "mark_sub_step"
    assert_includes names, "static_analyzer"
    assert_includes names, "read_tool_result"
  end

  # == Edge cases ==

  test "returns empty for auth_setup with no project and no tools" do
    session = create(:terminal_session, :auth_setup, user: @user, project: nil)

    assert_empty session.available_tools
  end

  test "disabled workflow tools are not included" do
    create(:tool, :workflow, :disabled, name: "disabled_wf_tool",
      display_name: "Disabled WF Tool")

    session = create(:terminal_session, user: @user, project: @project,
      session_type: "workflow_step", agent_type: nil)

    names = session.available_tools.map(&:name)

    refute_includes names, "disabled_wf_tool"
  end

  test "returns array that supports detect for MCP lookup" do
    session = create(:terminal_session, user: @user, project: @project,
      session_type: "workflow_step", agent_type: nil)

    found = session.available_tools.detect { |t| t.name == "list_sub_steps" }
    assert_not_nil found
    assert_equal "list_sub_steps", found.name
  end

  test "no duplicates when workflow tool is also in session.tools" do
    session = create(:terminal_session, user: @user, project: @project,
      session_type: "workflow_step", agent_type: nil)
    session.tools << @workflow_tool1

    tools = session.available_tools
    names = tools.map(&:name)
    assert_equal names.uniq.size, names.size
  end
end
