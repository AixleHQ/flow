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

  def feed(filters: {}, type: "all", viewer: @user, query: {})
    SessionsRunsFeed.new(project: @project, viewer: viewer, filters: filters, type: type, query: query)
  end

  def run_costing(cost_cents:, total_tokens: 0, **attrs)
    run = create(:workflow_run, workflow: @workflow, project: @project, user: @user, **attrs)
    step = create(:step, workflow: @workflow, position: run.id)
    session = create(:terminal_session, project: @project, user: @user, session_type: "workflow_step",
                                        agent_type: "claude_code", cost_cents: cost_cents, total_tokens: total_tokens)
    create(:step_run, workflow_run: run, step: step, terminal_session: session)
    run
  end

  def kinds_and_ids(page)
    page.entries.map { |e| [ e.kind, e.record.id ] }
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

  test "cancelled matches a cancelled session and a cancelled run alike" do
    standalone(state: "finished")
    session = standalone(state: "cancelled")
    cancelled = create(:workflow_run, :cancelled, workflow: @workflow, project: @project, user: @user)

    entries = feed(filters: { status: "cancelled" }).page(page: 1, limit: 10).entries

    assert_equal [ [ "run", cancelled.id ], [ "session", session.id ] ].sort,
      entries.map { |e| [ e.kind, e.record.id ] }.sort
  end

  # Queueing is what an operator watches during a capacity squeeze, so it needs
  # to be answerable on the page where a project's work actually lives.
  test "queued finds a waiting standalone session" do
    waiting = standalone(state: "queued")
    standalone(state: "ready")

    entries = feed(filters: { status: "queued" }).page(page: 1, limit: 10).entries

    assert_equal [ [ "session", waiting.id ] ], entries.map { |e| [ e.kind, e.record.id ] }
  end

  test "queued finds a run whose step is waiting, though the run itself is running" do
    run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user)
    step_run = create(:step_run, :running, workflow_run: run)
    step_run.update!(terminal_session: create(:terminal_session, project: @project, user: @user,
                                              session_type: "workflow_step", state: "queued"))
    create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user)

    entries = feed(filters: { status: "queued" }).page(page: 1, limit: 10).entries

    assert_equal [ [ "run", run.id ] ], entries.map { |e| [ e.kind, e.record.id ] },
      "a run is 'running' while its step waits, so state alone cannot answer this"
  end

  test "a run row reads Queued while its step waits for a slot" do
    run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user)
    step_run = create(:step_run, :running, workflow_run: run)
    step_run.update!(terminal_session: create(:terminal_session, project: @project, user: @user,
                                              session_type: "workflow_step", state: "queued"))

    payload = RunListEntryResource.new(run.reload).to_h

    assert_equal "queued", payload["state"], "the row must not claim work is happening while it waits"
  end

  test "a run still working is not reported as queued because another step waits" do
    run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user)
    working = create(:step_run, :running, workflow_run: run)
    working.update!(terminal_session: create(:terminal_session, project: @project, user: @user,
                                             session_type: "workflow_step", state: "ready"))
    waiting = create(:step_run, workflow_run: run)
    waiting.update!(terminal_session: create(:terminal_session, project: @project, user: @user,
                                             session_type: "workflow_step", state: "queued"))

    payload = RunListEntryResource.new(run.reload).to_h

    assert_equal "running", payload["state"], "one step waiting does not park a run that is executing"
  end

  test "pending no longer doubles as queued" do
    standalone(state: "queued")
    not_started = standalone(state: "not_started")

    entries = feed(filters: { status: "pending" }).page(page: 1, limit: 10).entries

    assert_equal [ [ "session", not_started.id ] ], entries.map { |e| [ e.kind, e.record.id ] }
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

  test "sorts sessions and runs together by cost, a run costing what its step sessions cost" do
    cheap = standalone(cost_cents: 50)
    pricey_run = run_costing(cost_cents: 900)
    mid = standalone(cost_cents: 300)

    by_cost = feed(query: { s: "cost_cents desc" }).page(page: 1, limit: 10)
    assert_equal [ [ "run", pricey_run.id ], [ "session", mid.id ], [ "session", cheap.id ] ], kinds_and_ids(by_cost)

    cheapest_first = feed(query: { s: "cost_cents asc" }).page(page: 1, limit: 10)
    assert_equal [ [ "session", cheap.id ], [ "session", mid.id ], [ "run", pricey_run.id ] ],
                 kinds_and_ids(cheapest_first)
  end

  test "sorts by tokens through the same step-session sums" do
    run = run_costing(cost_cents: 0, total_tokens: 40_000)
    session = standalone(total_tokens: 1_000)

    assert_equal [ [ "run", run.id ], [ "session", session.id ] ],
                 kinds_and_ids(feed(query: { s: "total_tokens desc" }).page(page: 1, limit: 10))
  end

  test "sorting by duration puts rows without one last in both directions" do
    freeze_time do
      long_run = create(:workflow_run, :completed, workflow: @workflow, project: @project, user: @user,
                                                   started_at: 3.hours.ago, completed_at: 1.hour.ago)
      short = standalone(state: "finished", started_at: 10.minutes.ago, finished_at: 5.minutes.ago)
      never_started = standalone(state: "cancelled", started_at: nil, finished_at: nil)

      longest = feed(query: { s: "duration_seconds desc" }).page(page: 1, limit: 10)
      assert_equal [ [ "run", long_run.id ], [ "session", short.id ], [ "session", never_started.id ] ],
                   kinds_and_ids(longest)

      shortest = feed(query: { s: "duration_seconds asc" }).page(page: 1, limit: 10)
      assert_equal [ [ "session", short.id ], [ "run", long_run.id ], [ "session", never_started.id ] ],
                   kinds_and_ids(shortest)
    end
  end

  test "a live session's duration runs up to now" do
    freeze_time do
      live = standalone(state: "ready", started_at: 2.hours.ago, finished_at: nil)
      done = standalone(state: "finished", started_at: 30.minutes.ago, finished_at: 20.minutes.ago)

      assert_equal [ [ "session", live.id ], [ "session", done.id ] ],
                   kinds_and_ids(feed(query: { s: "duration_seconds desc" }).page(page: 1, limit: 10))
    end
  end

  test "an unknown sort falls back to newest first" do
    older = standalone(created_at: 2.hours.ago, cost_cents: 999)
    newer = standalone(created_at: 1.hour.ago, cost_cents: 1)

    page = feed(query: { s: "initial_prompt desc" }).page(page: 1, limit: 10)

    assert_equal [ newer.id, older.id ], page.entries.map { |e| e.record.id }
    assert_equal "created_at desc", feed(query: { s: "initial_prompt desc" }).sort.to_s
  end

  test "the date range keeps both of its days whole, on both sides of the union" do
    travel_to Time.zone.parse("2026-10-08 12:00") do
      create(:workflow_run, workflow: @workflow, project: @project, user: @user,
                            created_at: Time.zone.parse("2026-09-23 23:59"))
      first_day = standalone(created_at: Time.zone.parse("2026-09-24 00:01"))
      last_day_run = create(:workflow_run, workflow: @workflow, project: @project, user: @user,
                                           created_at: Time.zone.parse("2026-10-01 23:59"))
      standalone(created_at: Time.zone.parse("2026-10-02 00:01"))

      page = feed(query: { created_from: "2026-09-24", created_until: "2026-10-01" }).page(page: 1, limit: 10)

      assert_equal [ [ "run", last_day_run.id ], [ "session", first_day.id ] ], kinds_and_ids(page)
    end
  end

  test "an unreadable date filters nothing" do
    standalone

    assert_equal 1, feed(query: { created_from: "yesterday" }).page(page: 1, limit: 10).pagy.count
  end

  test "workflow filter keeps that workflow's runs and drops standalone sessions" do
    standalone
    other_workflow = create(:workflow, scope: @project, name: "Nightly sync")
    create(:workflow_run, workflow: other_workflow, project: @project, user: @user)
    run = create(:workflow_run, workflow: @workflow, project: @project, user: @user)

    page = feed(filters: { workflow_id: @workflow.id }).page(page: 1, limit: 10)

    assert_equal [ [ "run", run.id ] ], kinds_and_ids(page)
  end

  test "workflow_options lists only workflows this project has run" do
    create(:workflow, scope: @project, name: "Never run")
    create(:workflow_run, workflow: @workflow, project: @project, user: @user)

    assert_equal [ { id: @workflow.id, name: "Weekly GA report" } ], feed.workflow_options
  end

  test "user_options lists only people who have run something here" do
    standalone
    create(:workflow_run, workflow: @workflow, project: @project, user: @other)
    create(:user, :employee, company: @company)

    assert_equal [ @user.id, @other.id ].sort, feed.user_options.pluck(:id).sort
  end
end
