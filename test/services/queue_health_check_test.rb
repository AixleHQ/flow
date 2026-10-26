# frozen_string_literal: true

require "test_helper"

class QueueHealthCheckTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, owner: @user, company: @company)
    @workflow = create(:workflow, scope: @project)
  end

  def run_pending_since(created_at, **attrs)
    create(:workflow_run,
      workflow: @workflow, project: @project, user: @user,
      state: "pending", created_at: created_at, **attrs)
  end

  test "a healthy installation reports nothing to act on" do
    run_pending_since(Time.current)

    stats = QueueHealthCheck.snapshot

    assert_equal 0, stats[:unstarted_runs]
    assert_equal 0, stats[:undispatched_runs]
    assert_equal 0, stats[:oldest_unstarted_seconds]
    assert_empty QueueHealthCheck.problems(stats)
  end

  # The exact shape of the 2026-09-12 outage: runs created, Temporal holding the
  # executions, no worker polling. Nothing was queued for a slot and the pool was
  # a third full, so every number the admission reconciler published stayed calm.
  test "runs nobody executes are reported even when the admission queue looks perfectly healthy" do
    run_pending_since(20.minutes.ago, relay_state: "dispatched")
    run_pending_since(10.minutes.ago, relay_state: "dispatched")

    stats = QueueHealthCheck.snapshot

    assert_equal 2, stats[:unstarted_runs]
    assert_operator stats[:oldest_unstarted_seconds], :>=, 20.minutes.to_i
    assert_equal 0, stats[:queued_admissions]
    assert_equal 0, stats[:undispatched_runs]

    problems = QueueHealthCheck.problems(stats)
    assert_equal 1, problems.size
    assert_match(/nothing is executing the queue/, problems.sole)
  end

  test "a run whose dispatch never reached Temporal is named as its own problem" do
    run_pending_since(10.minutes.ago, relay_state: "pending", relay_attempts: 1)

    stats = QueueHealthCheck.snapshot

    assert_equal 1, stats[:undispatched_runs]
    assert_match(/never reached Temporal/, QueueHealthCheck.problems(stats).first)
  end

  test "a run still inside the threshold is not yet a problem" do
    run_pending_since(QueueHealthCheck::UNSTARTED_RUN_THRESHOLD.ago + 30.seconds, relay_state: "dispatched")

    assert_equal 0, QueueHealthCheck.snapshot[:unstarted_runs]
  end

  # Someone asked for it to stop; it not starting is the requested outcome.
  test "a cancelled run is not counted as unstarted" do
    run_pending_since(20.minutes.ago, relay_state: "dispatched", stop_requested_at: Time.current)

    assert_equal 0, QueueHealthCheck.snapshot[:unstarted_runs]
  end

  # There are no factories for admissions on purpose: a reservation only exists by
  # going through the queue, so the tests build one the way production does.
  def admitted_session_with_operation(phase:, state: "uncertain")
    with_scope_defaults(project: 5)
    session = create(:terminal_session, user: @user, project: @project)
    admission = SessionAdmissionService.enqueue!(session)
    SessionAdmissionService.drain!
    session.update_columns(state: "running", started_at: 1.hour.ago)
    admission.reload.session_runtime_operations.create!(phase: phase, state: state)
    admission
  end

  # A pin is ordinary now: the reconciler ends one after a few minutes of proven
  # absence, so reporting every pin would page somebody for the ordinary end of a
  # cancelled session. It is still counted — an operator reading the numbers
  # should see it — it just is not a problem on its own.
  test "a reservation pinned by an unprovable runtime operation is counted but not reported" do
    admitted_session_with_operation(phase: "create_container")

    stats = QueueHealthCheck.snapshot

    assert_equal 1, stats[:pinned_reservations]
    assert_empty QueueHealthCheck.problems(stats).grep(/pinned/)
  end

  # The two cases nothing is going to end.
  test "a pin is reported when the operator has switched automatic release off" do
    admitted_session_with_operation(phase: "create_container")
    # After the helper, not before: it sets the project default through the same
    # settings block, so an earlier stub would be the one overwritten.
    Settings.stubs(:session_admission).returns(Hashie::Mash.new(project_default: 5, pinned_release_enabled: false))

    stats = QueueHealthCheck.snapshot

    assert_match(/automatic release is switched off/, QueueHealthCheck.problems(stats).grep(/pinned/).sole)
  end

  test "a pin that has outlived the confirmation window twice over is reported" do
    admission = admitted_session_with_operation(phase: "create_container")
    # Absence proved long ago and the slot still here: the reconciler is not
    # managing to release it, which is the part worth waking somebody for.
    admission.session_runtime_operations.pinning.update_all(absent_since: 1.hour.ago)

    stats = QueueHealthCheck.snapshot

    assert_equal 1, stats[:pinned_overdue]
    assert_match(/stayed pinned well past the confirmation window/, QueueHealthCheck.problems(stats).grep(/pinned/).sole)
  end

  # An `exec` nobody can account for is worth seeing elsewhere, but it costs no
  # capacity: by the time it could run, cleanup has proved the container gone.
  test "an unaccountable exec is not reported as held capacity" do
    admitted_session_with_operation(phase: "exec")

    assert_equal 0, QueueHealthCheck.snapshot[:pinned_reservations]
  end

  # A company may be lowered below what its projects reserved — a downgrade must
  # not be blocked by how the customer divided their capacity — so the drain
  # honours the company and the reservations are the promise being broken. The
  # only thing standing between that and silence is this line.
  test "a company whose projects reserve more than it has is reported" do
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 10)
    SessionConcurrencyLimit.set!(scope: @project, max_sessions: 3)
    other = create(:project, owner: @user, company: @company)
    SessionConcurrencyLimit.set!(scope: other, max_sessions: 2)
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 3)

    stats = QueueHealthCheck.snapshot

    assert_equal [ { company_id: @company.id, limit: 3, reserved: 5 } ], stats[:overcommitted_companies]
    assert_match(/above its limit of 3/, QueueHealthCheck.problems(stats).grep(/reservations/).sole)
  end

  test "a company within its reservations reports nothing" do
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 10)
    SessionConcurrencyLimit.set!(scope: @project, max_sessions: 4)

    stats = QueueHealthCheck.snapshot

    assert_empty stats[:overcommitted_companies]
    assert_empty QueueHealthCheck.problems(stats).grep(/reservations/)
  end

  def admission_in_pool(limit: 1, project: @project, admitted_at: nil, waiting_since: nil, drain: true)
    with_scope_defaults(project: limit)
    session = create(:terminal_session, user: @user, project: project)
    admission = SessionAdmissionService.enqueue!(session)
    SessionAdmissionService.drain! if drain
    admission.reload
    admission.update_columns(admitted_at: admitted_at) if admitted_at
    admission.update_columns(created_at: waiting_since) if waiting_since
    admission
  end

  # A slot granted hours ago, to a session that is now in `state`.
  def occupant(state:, finished_at: nil, **pool)
    admission = admission_in_pool(admitted_at: 3.hours.ago, **pool)
    admission.terminal_session.update_columns(state: state, finished_at: finished_at)
    admission
  end

  # The production shape of PALAD-AI-RAILS-39: one project's pool at its cap,
  # sessions finishing and the next one granted each time, the oldest wait
  # reported as an error every minute all the same.
  test "a long wait in a pool that keeps granting slots is not reported" do
    admission_in_pool(admitted_at: 5.minutes.ago)
    admission_in_pool(waiting_since: 2.hours.ago)

    stats = QueueHealthCheck.snapshot

    assert_operator stats[:oldest_admission_wait_seconds], :>=, 2.hours.to_i
    assert_empty stats[:stalled_pools]
    assert_empty QueueHealthCheck.problems(stats)
    assert_empty QueueHealthCheck.warnings(stats)
  end

  # The production shape of PALAD-AI-RAILS-3S: a project limited to one session
  # whose runs take hours grants nothing for as long as each one runs, with more
  # queued behind it all day. Admitted and still launching, or wrapping up, is as
  # live as running.
  %w[queued running ready finishing].each do |state|
    test "a pool full of a #{state} session is not reported however long the queue behind it" do
      occupant(state: state)
      admission_in_pool(waiting_since: 2.hours.ago)

      stats = QueueHealthCheck.snapshot

      assert_operator stats[:oldest_admission_wait_seconds], :>=, 2.hours.to_i
      assert_empty stats[:stalled_pools]
      assert_empty QueueHealthCheck.warnings(stats)
    end
  end

  TerminalSession::TERMINAL_STATES.each do |state|
    test "a slot still held by a session #{state} long ago is a warning, not an error" do
      occupant(state: state, finished_at: 40.minutes.ago)
      admission_in_pool(waiting_since: 40.minutes.ago)

      stats = QueueHealthCheck.snapshot

      assert_equal [ { key: "project:#{@project.id}", limit: 1, occupied: 1 } ],
                   stats[:stalled_pools].map { |pool| pool.slice(:key, :limit, :occupied) }
      assert_empty QueueHealthCheck.problems(stats)
      assert_match(/\Apool project:#{@project.id} has granted no slot for 30 minutes while a session waits \(oldest \d+s, 1\/1 slots occupied\)\z/,
                   QueueHealthCheck.warnings(stats).sole)
    end
  end

  # Its slot comes back only once the container is proven gone, and that can
  # take minutes after the session itself has ended.
  test "a session that has only just ended is not reported while its slot is being given back" do
    occupant(state: "finished", finished_at: 2.minutes.ago)
    admission_in_pool(waiting_since: 2.hours.ago)

    assert_empty QueueHealthCheck.snapshot[:stalled_pools]
  end

  test "a free slot nobody is granted while a session waits is a warning" do
    occupant(state: "running", limit: 2)
    admission_in_pool(limit: 2, waiting_since: 40.minutes.ago, drain: false)

    stats = QueueHealthCheck.snapshot

    assert_equal [ { key: "project:#{@project.id}", limit: 2, occupied: 1 } ],
                 stats[:stalled_pools].map { |pool| pool.slice(:key, :limit, :occupied) }
  end

  test "a pool under its own cap waiting on a company limit that running sessions fill is not reported" do
    with_company_limit(@company, 1)
    occupant(state: "running", limit: 4, project: create(:project, owner: @user, company: @company))
    admission_in_pool(limit: 4, waiting_since: 2.hours.ago)

    assert_empty QueueHealthCheck.snapshot[:stalled_pools]
  end

  test "a company slot held by a session that ended long ago is reported on the pool waiting for it" do
    with_company_limit(@company, 1)
    occupant(state: "failed", finished_at: 40.minutes.ago, limit: 4,
             project: create(:project, owner: @user, company: @company))
    admission_in_pool(limit: 4, waiting_since: 40.minutes.ago)

    assert_equal [ "project:#{@project.id}" ], QueueHealthCheck.snapshot[:stalled_pools].pluck(:key)
  end

  test "call returns the snapshot it reported" do
    run_pending_since(20.minutes.ago, relay_state: "dispatched")

    assert_equal QueueHealthCheck.snapshot.keys.sort, QueueHealthCheck.call.keys.sort
    assert_equal 1, QueueHealthCheck.call[:unstarted_runs]
  end
end
