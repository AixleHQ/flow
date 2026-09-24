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
    with_admission(project: 5)
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

  test "call returns the snapshot it reported" do
    run_pending_since(20.minutes.ago, relay_state: "dispatched")

    assert_equal QueueHealthCheck.snapshot.keys.sort, QueueHealthCheck.call.keys.sort
    assert_equal 1, QueueHealthCheck.call[:unstarted_runs]
  end
end
