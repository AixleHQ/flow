# frozen_string_literal: true

require "test_helper"

# The guard for docs/design/tool-attachment.md: a session gets a tool only when
# its workflow, step or the session itself attached it. A rule that serves any
# other tool fails here.
class Tools::PlumbingTest < ActiveSupport::TestCase
  ALWAYS = %w[fail_session finish_session list_sub_steps mark_sub_step].freeze
  PLUMBING = (ALWAYS + %w[get_config_item read_tool_result]).sort.freeze

  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    Tools::Reconciler.run!
  end

  test "exactly the six plumbing tools have an injection rule" do
    named = Tools::Registry.definitions.values.reject { |d| d.inject_rules.empty? }.map(&:name).sort

    assert_equal PLUMBING, named
  end

  # A project where every integration is connected and every old injection
  # condition holds, with custom tools in the project.
  def connect_everything
    create(:integration, :coder, :active, company: @company, project: @project, connected_by: @user)
    azure = create(:integration, :azure_devops, :active, company: @company, project: @project, connected_by: @user)
    create(:integration, :active, provider: :slack, company: @company, project: @project)
    create(:integration, :active, provider: :teams, company: @company, project: @project)
    github = create(:integration, company: @company, connected_by: @user, status: :active)
    @tracker = create(:project_tracker, :primary, integration: azure)
    @azure_repository = create(:repository, :azure_devops, integration: azure, scope: @project)
    @github_repository = create(:repository, integration: github, scope: @project)
    create(:tool, scope: @project, name: "project_tool", display_name: "Project Tool", docker_image: "pt:1.0")
  end

  def tracker_step_run
    workflow = create(:workflow, scope: @project)
    run = create(:workflow_run, workflow: workflow, project: @project, user: @user,
                                shared_context: { "tracker" => { "project_tracker_id" => @tracker.id } })
    create(:step_run, workflow_run: run, step: create(:step, workflow: workflow))
  end

  def sessions
    connect_everything
    repositories = [ @azure_repository, @github_repository ]
    {
      "workflow step" => create(:terminal_session, user: @user, project: @project,
                                session_type: "workflow_step", agent_type: nil, step_run: tracker_step_run),
      "non-interactive agent" => create(:terminal_session, :agent_session, user: @user, project: @project,
                                        mode: "non_interactive", initial_prompt: "run"),
      "interactive agent" => create(:terminal_session, :agent_session, user: @user, project: @project)
    }.each_value { |session| session.repositories << repositories }
  end

  test "a session that attached nothing gets only the four unconditional tools" do
    sessions.each do |kind, session|
      assert_equal ALWAYS.sort, session.available_tools.map(&:name).sort, kind
    end
  end

  test "a session that attached a tool gets it and no other non-plumbing tool" do
    sessions.each do |kind, session|
      %w[coder_ssh_exec board_move_task tracker_get_issue azure_devops_list_builds refresh_github_token].each do |name|
        session.tools << Tool.shadow_for(Tools::Registry.fetch(name))
        extra = session.reload.available_tools.map(&:name) - ALWAYS
        assert_equal [ name ], extra, "#{kind}: #{name}"
        session.tools.delete(Tool.shadow_for(Tools::Registry.fetch(name)))
      end
    end
  end

  test "an attached container tool adds read_tool_result and nothing else" do
    session = sessions["interactive agent"]
    session.tools << create(:tool, scope: @project, name: "my_linter", display_name: "My Linter", docker_image: "l:1")

    assert_equal (ALWAYS + %w[my_linter read_tool_result]).sort, session.reload.available_tools.map(&:name).sort
  end

  test "an attached config item adds get_config_item and nothing else" do
    session = sessions["interactive agent"]
    session.config_items << create(:config_item, scope: @project)

    assert_equal (ALWAYS + %w[get_config_item]).sort, session.reload.available_tools.map(&:name).sort
  end
end
