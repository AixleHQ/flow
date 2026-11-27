# frozen_string_literal: true

require "test_helper"

class TerminalSessionAvailableToolsTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)

    # Platform tools come from the code registry; shadow rows materialize on
    # demand. static_analyzer stands in for an explicitly attached container
    # tool. It lives in a SIBLING project so it is never auto-inherited into
    # @project's sessions — it only shows up when a test attaches it explicitly.
    @other_project = create(:project, company: @company, owner: @user)
    @system_tool = create(:tool, name: "static_analyzer", scope: @other_project,
      display_name: "Static Analyzer", docker_image: "analyzer:latest",
      execution_mode: :container)
  end

  # The explicitly attached container tool, owned by the session's own project.
  def local_container_tool
    @local_container_tool ||= create(:tool, name: "static_analyzer", scope: @project,
      display_name: "Static Analyzer", docker_image: "analyzer:latest", execution_mode: :container)
  end

  test "a tool of another project is never available, even when attached" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    session.tools << @system_tool

    refute_includes session.available_tools.map(&:name), "static_analyzer"
  end

  test "an attached tool stops being served once it is archived" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    session.tools << local_container_tool
    assert_includes session.available_tools.map(&:name), "static_analyzer"

    local_container_tool.soft_delete!

    refute_includes session.reload.available_tools.map(&:name), "static_analyzer"
  end

  # == Plumbing: the only tools served without an attachment ==
  # docs/design/tool-attachment.md. The exhaustive guard is Tools::PlumbingTest.

  PLUMBING = %w[finish_session fail_session list_sub_steps mark_sub_step].freeze

  def attach(session, name)
    session.tools << Tool.shadow_for(Tools::Registry.fetch(name))
  end

  test "a workflow step session that attached nothing gets only the plumbing tools" do
    session = create(:terminal_session, user: @user, project: @project,
      session_type: "workflow_step", agent_type: nil)

    assert_equal PLUMBING.sort, session.available_tools.map(&:name).sort
  end

  test "an agent session that attached nothing gets only the plumbing tools, interactive or not" do
    interactive = create(:terminal_session, :agent_session, user: @user, project: @project)
    unattended = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "non_interactive", initial_prompt: "run")

    assert_equal PLUMBING.sort, interactive.available_tools.map(&:name).sort
    assert_equal PLUMBING.sort, unattended.available_tools.map(&:name).sort
  end

  test "board and chat tools reach a workflow step only when attached" do
    session = create(:terminal_session, user: @user, project: @project,
      session_type: "workflow_step", agent_type: nil)
    refute_includes session.available_tools.map(&:name), "board_list_tasks"
    refute_includes session.available_tools.map(&:name), "chat_post_message"

    attach(session, "board_list_tasks")
    names = session.reload.available_tools.map(&:name)

    assert_includes names, "board_list_tasks"
    refute_includes names, "chat_post_message"
    refute_includes names, "board_move_task"
  end

  test "workflow tools are not served to a session with no project, apart from plumbing" do
    session = create(:terminal_session, :auth_setup, user: @user, project: nil)

    assert_equal PLUMBING.sort, session.available_tools.map(&:name).sort
  end

  # == refresh_github_token: attached, not injected ==

  test "refresh_github_token is not served to a session holding a GitHub repository" do
    integration = create(:integration, company: @company, connected_by: @user, status: :active)
    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    session.repositories << create(:repository, integration: integration, scope: @project)

    refute_includes session.available_tools.map(&:name), "refresh_github_token"
  end

  test "refresh_github_token is served when attached" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    attach(session, "refresh_github_token")

    assert_includes session.available_tools.map(&:name), "refresh_github_token"
  end

  # == Coder ==

  test "Coder tools are not served because a Coder connection exists" do
    create(:integration, :coder, :active, company: @company, project: @project, connected_by: @user) if Integration.respond_to?(:coder)
    session = create(:terminal_session, :agent_session, user: @user, project: @project)

    assert session.available_tools.map(&:name).none? { |n| n.start_with?("coder_") }
  end

  # == Azure DevOps: attached like any other tool ==

  test "Azure repository tools are not served for a session holding an Azure repository" do
    integration = create(:integration, :azure_devops, :active, company: @company,
      project: @project, connected_by: @user)
    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    session.repositories << create(:repository, :azure_devops, integration: integration, scope: @project)

    assert session.available_tools.map(&:name).none? { |n| n.start_with?("azure_devops_") }

    attach(session, "azure_devops_create_pull_request")
    names = session.reload.available_tools.map(&:name)

    assert_includes names, "azure_devops_create_pull_request"
    refute_includes names, "azure_devops_reply_pull_request_thread"
  end

  test "Azure build tools are not served because the connection exists" do
    create(:integration, :azure_devops, :active, company: @company, project: @project, connected_by: @user)
    session = create(:terminal_session, :agent_session, user: @user, project: @project)

    assert session.available_tools.map(&:name).none? { |n| n.start_with?("azure_devops_") }

    attach(session, "azure_devops_list_builds")
    assert_includes session.reload.available_tools.map(&:name), "azure_devops_list_builds"
  end

  test "tracker tools are attached, never served by a connection alone" do
    integration = create(:integration, :azure_devops, :active, company: @company, project: @project, connected_by: @user)
    create(:project_tracker, :primary, integration: integration)
    session = create(:terminal_session, :agent_session, user: @user, project: @project)

    refute session.available_tools.map(&:name).any? { |n| n.start_with?("tracker_") }

    attach(session, "tracker_get_issue")
    assert_includes session.reload.available_tools.map(&:name), "tracker_get_issue"
  end

  test "a run a tracker event started gets no tracker tool unless it is attached" do
    integration = create(:integration, :azure_devops, :active, company: @company, project: @project, connected_by: @user)
    tracker = create(:project_tracker, :primary, integration: integration)
    workflow = create(:workflow, scope: @project)
    run = create(:workflow_run, workflow: workflow, project: @project, user: @user,
                                shared_context: { "tracker" => { "project_tracker_id" => tracker.id } })
    step_run = create(:step_run, workflow_run: run, step: create(:step, workflow: workflow))
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: step_run)

    refute_includes session.available_tools.map(&:name), "tracker_transition_issue"

    attach(session, "tracker_transition_issue")
    assert_includes session.reload.available_tools.map(&:name), "tracker_transition_issue"
  end

  # == System tools: explicitly attached ==

  test "system tool is NOT included unless explicitly selected" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project)

    names = session.available_tools.map(&:name)

    refute_includes names, "static_analyzer"
  end

  test "system tool is included when explicitly added to session tools" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    session.tools << local_container_tool

    names = session.available_tools.map(&:name)

    assert_includes names, "static_analyzer"
  end

  # == Internal tools: auto-injected when container tools present ==

  test "internal tools are auto-injected when container tool is attached" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    session.tools << local_container_tool

    names = session.available_tools.map(&:name)

    assert_includes names, "read_tool_result"
  end

  test "internal tools are NOT present when no container tools attached" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project)

    names = session.available_tools.map(&:name)

    refute_includes names, "read_tool_result"
  end

  test "internal tools are auto-injected when custom container tool is attached" do
    custom_tool = create(:tool, scope: @project, name: "my_linter",
      display_name: "My Linter", docker_image: "linter:1.0")

    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    session.tools << custom_tool

    names = session.available_tools.map(&:name)

    assert_includes names, "read_tool_result"
  end

  test "project custom tools do not give a session read_tool_result" do
    create(:tool, scope: @project, name: "project_tool",
      display_name: "Project Tool", docker_image: "pt:1.0")

    session = create(:terminal_session, :agent_session, user: @user, project: @project)

    refute_includes session.available_tools.map(&:name), "read_tool_result"
  end

  # == Custom tools ==

  test "custom tools from session.tools are included" do
    custom_tool = create(:tool, scope: @project, name: "my_linter",
      display_name: "My Linter", docker_image: "linter:1.0")

    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    session.tools << custom_tool

    names = session.available_tools.map(&:name)

    assert_includes names, "my_linter"
  end

  test "a session that attached no custom tool gets none of the project's custom tools" do
    create(:tool, scope: @project, name: "project_tool",
      display_name: "Project Tool", docker_image: "pt:1.0")

    session = create(:terminal_session, :agent_session, user: @user, project: @project)

    refute_includes session.available_tools.map(&:name), "project_tool"
  end

  test "a session that attached a custom tool gets it and no other custom tool" do
    create(:tool, scope: @project, name: "project_tool",
      display_name: "Project Tool", docker_image: "pt:1.0")
    custom_tool = create(:tool, scope: @project, name: "my_tool",
      display_name: "My Tool", docker_image: "mt:1.0")

    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    session.tools << custom_tool

    names = session.available_tools.map(&:name)

    assert_includes names, "my_tool"
    refute_includes names, "project_tool"
  end

  # == Workflow step with mixed tools ==

  test "workflow_step session gets plumbing and explicitly selected tools" do
    session = create(:terminal_session, user: @user, project: @project,
      session_type: "workflow_step", agent_type: nil)
    session.tools << local_container_tool

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

  test "a disabled shadow row keeps its tool out of the injected set" do
    Tools::Reconciler.run!
    Tool.code_source.find_by!(name: "mark_sub_step").update_columns(enabled: false)

    session = create(:terminal_session, user: @user, project: @project,
      session_type: "workflow_step", agent_type: nil)

    names = session.available_tools.map(&:name)

    refute_includes names, "mark_sub_step"
    assert_includes names, "list_sub_steps"
  end

  test "returns array that supports detect for MCP lookup" do
    session = create(:terminal_session, user: @user, project: @project,
      session_type: "workflow_step", agent_type: nil)

    found = session.available_tools.detect { |t| t.name == "list_sub_steps" }
    assert_not_nil found
    assert_equal "list_sub_steps", found.name
  end

  test "no duplicates when an injected tool is also in session.tools" do
    session = create(:terminal_session, user: @user, project: @project,
      session_type: "workflow_step", agent_type: nil)
    session.tools << Tool.shadow_for(Tools::Registry.fetch("list_sub_steps"))

    tools = session.available_tools
    names = tools.map(&:name)
    assert_equal names.uniq.size, names.size
  end
end
