# frozen_string_literal: true

require "test_helper"

class Integrations::BackfillTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @workflow = create(:workflow, scope: @project)
    @coder = create(:integration, :coder, :active, company: @company, project: @project, connected_by: @user)
    @backfill = Integrations::Backfill.new(logger: Logger.new(nil))
  end

  def teams(name, tenant, **attrs)
    Integration.create!(provider: :teams, company: @company, connected_by: @user, name: name, status: :active,
                        settings: { "tenant_id" => tenant }, **attrs)
  end

  test "a workflow gets the project's Coder, every chat install it sees and its Azure DevOps connections" do
    first = teams("First", "00000000-0000-4000-8000-0000000000c1")
    second = teams("Second", "00000000-0000-4000-8000-0000000000c2")
    azure = create(:integration, :azure_devops, :active, company: @company, project: @project, connected_by: @user)

    assert_equal 4, @backfill.workflows

    assert_equal [ @coder.id, first.id, second.id, azure.id ].sort, @workflow.reload.base_integration_ids.sort
  end

  test "nothing is attached for a provider the project has no integration of, or that is not active" do
    @coder.update_columns(status: "error")
    create(:integration, :github_pat, :active, company: @company, project: @project, connected_by: @user)

    assert_equal 0, @backfill.workflows
    assert_empty @workflow.reload.base_integration_ids
  end

  test "the company's Coder is attached only when the project has none, and the earliest of several wins" do
    @coder.update_columns(status: "error")
    wide = create(:integration, :coder, :active, company: @company, connected_by: @user)
    create(:integration, :coder, :active, company: @company, connected_by: @user)

    @backfill.workflows

    assert_equal [ wide.id ], @workflow.reload.base_integration_ids
  end

  test "another project's integrations are not attached" do
    other = create(:project, company: @company, owner: @user)
    create(:integration, :coder, :active, company: @company, project: other, connected_by: @user)
    @coder.update_columns(status: "inactive")

    @backfill.workflows

    assert_empty @workflow.reload.base_integration_ids
  end

  test "workflows are backfilled once: a second run adds nothing" do
    @backfill.workflows

    assert_equal 0, @backfill.workflows
    assert_equal [ @coder.id ], @workflow.reload.base_integration_ids
  end

  test "a system workflow gets nothing" do
    system = create(:workflow, :system)

    @backfill.workflows

    assert_empty system.reload.base_integration_ids
  end

  test "every state a session can still be used in gets its set, ended ones get none" do
    sessions = %w[not_started queued running ready finishing suspended].index_with do |state|
      create(:terminal_session, :agent_session, user: @user, project: @project, state: state)
    end
    ended = %w[finished failed cancelled restored].map do |state|
      create(:terminal_session, :agent_session, user: @user, project: @project, state: state)
    end

    @backfill.sessions

    sessions.each_value { |session| assert_equal [ @coder.id ], session.reload.integration_ids }
    ended.each { |session| assert_empty session.reload.integration_ids }
  end

  test "a workflow session gets its workflow's set and its origin" do
    @workflow.merge_config!("base_integration_ids" => [ @coder.id ])
    origin = teams("Origin", "00000000-0000-4000-8000-0000000000c3")
    run = create(:workflow_run, workflow: @workflow, project: @project, user: @user,
                                shared_context: { "chat" => { "provider" => "teams", "integration_id" => origin.id } })
    session = create(:terminal_session, :running, user: @user, project: @project, session_type: "workflow_step")
    create(:step_run, workflow_run: run, step: create(:step, workflow: @workflow), terminal_session: session)

    @backfill.sessions

    assert_equal [ @coder.id, origin.id ].sort, session.reload.integration_ids.sort
  end

  test "a session that already has a set is left alone, and SINCE limits the run to newer sessions" do
    old = create(:terminal_session, :agent_session, user: @user, project: @project, state: "running",
                                                    created_at: 3.days.ago)
    had = create(:terminal_session, :agent_session, user: @user, project: @project, state: "running")
    own = create(:integration, :coder, :active, company: @company, project: @project, connected_by: @user)
    had.integrations << own

    @backfill.sessions(since: 1.day.ago)

    assert_empty old.reload.integration_ids
    assert_equal [ own.id ], had.reload.integration_ids
  end
end
