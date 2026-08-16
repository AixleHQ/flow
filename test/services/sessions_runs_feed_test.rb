# frozen_string_literal: true

require "test_helper"

class SessionsRunsFeedTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @other = create(:user, :employee, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @workflow = create(:workflow, scope: @project, name: "Weekly GA report")
  end

  def feed(filters: {}, type: "all", viewer: @user)
    SessionsRunsFeed.new(project: @project, viewer: viewer, filters: filters, type: type)
  end

  def standalone(**attrs)
    create(:terminal_session, :agent_session, project: @project, user: @user, **attrs)
  end

  test "interleaves standalone sessions and workflow runs newest first" do
    older_session = standalone(created_at: 3.hours.ago)
    run = create(:workflow_run, workflow: @workflow, project: @project, user: @user, created_at: 2.hours.ago)
    newer_session = standalone(created_at: 1.hour.ago)

    page = feed.page(page: 1, limit: 10)

    assert_equal 3, page.pagy.count
    assert_equal [ [ "session", newer_session.id ], [ "run", run.id ], [ "session", older_session.id ] ],
                 page.entries.map { |e| [ e.kind, e.record.id ] }
  end

  test "workflow-step sessions never take a top-level row" do
    run = create(:workflow_run, workflow: @workflow, project: @project, user: @user)
    step = create(:step, workflow: @workflow, position: 1)
    step_session = create(:terminal_session, project: @project, user: @user, session_type: "workflow_step",
                                             agent_type: "claude_code")
    create(:step_run, workflow_run: run, step: step, terminal_session: step_session)

    page = feed.page(page: 1, limit: 10)

    assert_equal [ [ "run", run.id ] ], page.entries.map { |e| [ e.kind, e.record.id ] }
  end

  test "auth and tool setup sessions stay out of the feed entirely" do
    create(:terminal_session, project: @project, user: @user, session_type: "auth_setup")
    create(:terminal_session, project: @project, user: @user, session_type: "tool_setup", agent_type: "claude_code")

    assert_equal 0, feed.page(page: 1, limit: 10).pagy.count
  end

  test "type filter selects one side of the union" do
    session = standalone
    run = create(:workflow_run, workflow: @workflow, project: @project, user: @user)

    assert_equal [ session.id ], feed(type: "solo").page(page: 1, limit: 10).entries.map { |e| e.record.id }
    assert_equal [ run.id ], feed(type: "run").page(page: 1, limit: 10).entries.map { |e| e.record.id }
  end

  test "status maps one vocabulary onto both state machines" do
    finished = standalone(state: "finished")
    completed_run = create(:workflow_run, :completed, workflow: @workflow, project: @project, user: @user)
    standalone(state: "ready")

    ids = feed(filters: { status: "completed" }).page(page: 1, limit: 10).entries.map { |e| e.record.id }

    assert_equal [ finished.id, completed_run.id ].sort, ids.sort
  end

  test "cancelled matches runs only, since sessions have no such state" do
    standalone(state: "finished")
    cancelled = create(:workflow_run, :cancelled, workflow: @workflow, project: @project, user: @user)

    entries = feed(filters: { status: "cancelled" }).page(page: 1, limit: 10).entries

    assert_equal [ [ "run", cancelled.id ] ], entries.map { |e| [ e.kind, e.record.id ] }
  end

  test "search matches a session's prompt and a run's workflow name" do
    matching_session = standalone(initial_prompt: "audit the GA4 property")
    standalone(initial_prompt: "rename the importer")
    run = create(:workflow_run, workflow: @workflow, project: @project, user: @user)

    ids = feed(filters: { search: "ga" }).page(page: 1, limit: 10).entries.map { |e| e.record.id }

    assert_equal [ matching_session.id, run.id ].sort, ids.sort
  end

  test "search escapes wildcards instead of treating them as a pattern" do
    standalone(initial_prompt: "rename the importer")

    assert_equal 0, feed(filters: { search: "%" }).page(page: 1, limit: 10).pagy.count
  end

  test "search does not surface another user's private session that merely matches the term" do
    private_session = create(:terminal_session, :agent_session, :running, project: @project, user: @other,
                                                                          initial_prompt: "rotate the API keys")
    assert_not private_session.user.share_active_sessions?, "fixture assumption: sharing is off by default"

    assert_equal 0, feed(filters: { search: "rotate" }, viewer: @user).page(page: 1, limit: 10).pagy.count
  end

  test "search still surfaces a session its own owner searches for" do
    private_session = create(:terminal_session, :agent_session, :running, project: @project, user: @other,
                                                                          initial_prompt: "rotate the API keys")

    ids = feed(filters: { search: "rotate" }, viewer: @other).page(page: 1, limit: 10).entries.map { |e| e.record.id }

    assert_equal [ private_session.id ], ids
  end

  test "search surfaces a shared session that matches the term" do
    @other.update!(share_completed_sessions: true)
    shared_session = create(:terminal_session, :agent_session, state: "finished", project: @project, user: @other,
                                                                initial_prompt: "rotate the API keys")

    ids = feed(filters: { search: "rotate" }, viewer: @user).page(page: 1, limit: 10).entries.map { |e| e.record.id }

    assert_equal [ shared_session.id ], ids
  end

  test "agent filter reaches a run through its step sessions" do
    standalone(agent_type: "codex")
    run = create(:workflow_run, workflow: @workflow, project: @project, user: @user)
    step = create(:step, workflow: @workflow, position: 1)
    session = create(:terminal_session, project: @project, user: @user, session_type: "workflow_step",
                                        agent_type: "claude_code")
    create(:step_run, workflow_run: run, step: step, terminal_session: session)

    entries = feed(filters: { agent_type: "claude_code" }).page(page: 1, limit: 10).entries

    assert_equal [ [ "run", run.id ] ], entries.map { |e| [ e.kind, e.record.id ] }
  end

  test "a run with several sessions on the same runtime is still one row" do
    run = create(:workflow_run, workflow: @workflow, project: @project, user: @user)
    2.times do |i|
      step = create(:step, workflow: @workflow, position: i + 1)
      session = create(:terminal_session, project: @project, user: @user, session_type: "workflow_step",
                                          agent_type: "claude_code")
      create(:step_run, workflow_run: run, step: step, terminal_session: session)
    end

    assert_equal 1, feed(filters: { agent_type: "claude_code" }).page(page: 1, limit: 10).pagy.count
  end

  test "user filter narrows both sides" do
    mine = standalone
    create(:workflow_run, workflow: @workflow, project: @project, user: @other)

    entries = feed(filters: { user_id: @user.id }).page(page: 1, limit: 10).entries

    assert_equal [ [ "session", mine.id ] ], entries.map { |e| [ e.kind, e.record.id ] }
  end

  test "paginates across the union rather than per table" do
    5.times { |i| standalone(created_at: (10 - i).minutes.ago) }
    create(:workflow_run, workflow: @workflow, project: @project, user: @user, created_at: 1.minute.ago)

    first = feed.page(page: 1, limit: 4)
    second = feed.page(page: 2, limit: 4)

    assert_equal 6, first.pagy.count
    assert_equal 4, first.entries.size
    assert_equal 2, second.entries.size
    assert_empty first.entries.map { |e| [ e.kind, e.record.id ] } & second.entries.map { |e| [ e.kind, e.record.id ] }
  end

  test "user_options lists only people who have run something here" do
    standalone
    create(:workflow_run, workflow: @workflow, project: @project, user: @other)
    create(:user, :employee, company: @company)

    assert_equal [ @user.id, @other.id ].sort, feed.user_options.pluck(:id).sort
  end
end
