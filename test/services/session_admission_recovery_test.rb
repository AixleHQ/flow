# frozen_string_literal: true

require "test_helper"

# Recovery is the half of the queue nobody exercises by hand: a reservation is
# only safe to hold forever if something eventually proves the runtime is gone,
# and only safe to reap if something proves it is not merely waiting.
class SessionAdmissionRecoveryTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    # Only project sessions are queued at all, so recovery is only ever about one.
    @project = create(:project, owner: @user, company: @user.companies.first)
    with_ceiling(1)
  end

  def admit(session)
    admission = SessionAdmissionService.enqueue!(session)
    SessionAdmissionService.drain!
    admission.reload
  end

  test "a closed container workflow releases the reservation it left behind" do
    session = create(:terminal_session, user: @user, project: @project, state: "running", started_at: 1.hour.ago)
    admission = admit(session)
    session.update!(state: "running", started_at: 1.hour.ago)
    admission.update!(launch_state: "acknowledged", runtime_id: nil)

    runtime = ContainerRuntime::DockerRuntime.new
    ContainerRuntime.stubs(:build).returns(runtime)
    runtime.expects(:session_absent?).never
    stub_closed_workflow(session.workflow_id)

    SessionAdmissionReconciler.run

    assert admission.reload.released_at, "a workflow that ended must not keep the slot"
    # Reaching reconciliation at all means the workflow's own cleanup never
    # settled the session, so "it just ended" is a failure, not a success.
    assert_equal "failed", session.reload.state
  end

  test "an unresolved runtime operation keeps its slot through reconciliation" do
    session = create(:terminal_session, user: @user, project: @project, state: "running", started_at: 1.hour.ago)
    admission = admit(session)
    session.update!(state: "running", started_at: 1.hour.ago)
    admission.update!(launch_state: "acknowledged")
    admission.session_runtime_operations.create!(phase: "create_container", state: "uncertain")

    TemporalService.expects(:client).never
    SessionAdmissionReconciler.run

    assert_nil admission.reload.released_at
  end

  test "a closed workflow strands its in-flight operation instead of leaving it silent" do
    session = create(:terminal_session, user: @user, project: @project, state: "cancelled", started_at: 2.hours.ago)
    admission = admit(session)
    session.update!(state: "cancelled", started_at: 2.hours.ago)
    admission.update!(launch_state: "acknowledged", runtime_id: nil)
    op = admission.session_runtime_operations.create!(phase: "create_container", state: "in_flight")

    runtime = ContainerRuntime::DockerRuntime.new
    ContainerRuntime.stubs(:build).returns(runtime)
    stub_closed_workflow(session.workflow_id)

    SessionAdmissionReconciler.run

    # in_flight reads as ordinary provisioning load, so a slot pinned this way
    # stayed invisible for hours. Once the workflow is closed nobody can report
    # that result, and `uncertain` is the number an operator is alerted on.
    assert_equal "uncertain", op.reload.state
    assert_equal 1, SessionAdmissionReconciler.snapshot[:uncertain_operations]
    assert_nil admission.reload.released_at, "the reservation still waits for an operator"
  end

  test "a wedged admission is examined rather than skipped over" do
    session = create(:terminal_session, user: @user, project: @project, state: "cancelled", started_at: 2.hours.ago)
    admission = admit(session)
    session.update!(state: "cancelled", started_at: 2.hours.ago)
    # Output collection is a separate concern and reaches the real strategy;
    # marking it done keeps this test on the deletion it is about.
    admission.update!(launch_state: "acknowledged", runtime_id: "runtime-id",
                      phase_state: { "cleanup_collected" => true })
    admission.session_runtime_operations.create!(phase: "create_container", state: "in_flight")

    runtime = ContainerRuntime::DockerRuntime.new
    ContainerRuntime.stubs(:build).returns(runtime)
    # The workload outliving its cancelled workflow is the whole failure: the
    # reconciler used to skip these, so nothing ever deleted it.
    runtime.expects(:cleanup_session).with("runtime-id")
    runtime.stubs(:session_absent?).returns(false, true)
    stub_closed_workflow(session.workflow_id)

    SessionAdmissionReconciler.run

    assert_nil admission.reload.released_at
  end

  # AD-5 holds a slot so a late Pod never finds its seat handed to someone else,
  # and only a create or a start can produce that Pod. An `exec` runs inside a
  # container this very pass has just proved absent, so retaining the reservation
  # for one pinned capacity nothing could reclaim without an operator — which is
  # how sessions that timed out mid-exec ate the installation's slots one by one.
  test "an unaccountable exec stops pinning the slot once the container is gone" do
    session = create(:terminal_session, user: @user, project: @project, state: "cancelled", started_at: 2.hours.ago)
    admission = admit(session)
    session.update!(state: "cancelled", started_at: 2.hours.ago)
    admission.update!(launch_state: "acknowledged", runtime_id: "runtime-id",
                      phase_state: { "cleanup_collected" => true })
    op = admission.session_runtime_operations.create!(phase: "exec", state: "in_flight")

    runtime = ContainerRuntime::DockerRuntime.new
    ContainerRuntime.stubs(:build).returns(runtime)
    runtime.expects(:cleanup_session).with("runtime-id")
    runtime.stubs(:session_absent?).returns(false, true)
    stub_closed_workflow(session.workflow_id)

    SessionAdmissionReconciler.run

    assert admission.reload.released_at, "a container that is gone cannot host a late exec"
    # Still recorded honestly: the operation is a diagnostic, not a lien.
    assert_equal "uncertain", op.reload.state
    stats = SessionAdmissionReconciler.snapshot
    assert_equal 1, stats[:uncertain_operations]
    assert_equal 0, stats[:pinned_reservations]
  end

  # AD-5 holds the slot for a create nobody can account for, so a late Pod never
  # lands on someone else's. Production showed the other edge of that: on
  # 2026-09-17 the watchdog — itself only running because its supervisor had
  # finally been restarted — reported a slot pinned for hours while the workload
  # behind it was provably gone on every single pass. The pin has to end by
  # itself, and the evidence it ends on is the absence this very pass proved.
  test "a pinned reservation is not released by the first pass that proves absence" do
    session = create(:terminal_session, user: @user, project: @project, state: "cancelled", started_at: 2.hours.ago)
    admission = admit(session)
    session.update!(state: "cancelled", started_at: 2.hours.ago)
    admission.update!(launch_state: "acknowledged", runtime_id: "runtime-id",
                      phase_state: { "cleanup_collected" => true })
    op = admission.session_runtime_operations.create!(phase: "create_container", state: "uncertain")

    runtime = ContainerRuntime::DockerRuntime.new
    ContainerRuntime.stubs(:build).returns(runtime)
    runtime.stubs(:session_absent?).returns(true)
    stub_closed_workflow(session.workflow_id)

    SessionAdmissionReconciler.run

    assert_nil admission.reload.released_at, "one look is not a settled absence"
    assert op.reload.absent_since, "the pass that proved absence starts the clock"
    assert_equal "uncertain", op.state
  end

  test "a pinned reservation is released once proven absence has held the window" do
    session = create(:terminal_session, user: @user, project: @project, state: "cancelled", started_at: 2.hours.ago)
    admission = admit(session)
    session.update!(state: "cancelled", started_at: 2.hours.ago)
    admission.update!(launch_state: "acknowledged", runtime_id: "runtime-id",
                      phase_state: { "cleanup_collected" => true })
    op = admission.session_runtime_operations.create!(phase: "create_container", state: "uncertain")
    # What earlier passes proved, without spending the window in real time.
    op.update!(absent_since: 10.minutes.ago)

    runtime = ContainerRuntime::DockerRuntime.new
    ContainerRuntime.stubs(:build).returns(runtime)
    runtime.stubs(:session_absent?).returns(true)
    stub_closed_workflow(session.workflow_id)

    SessionAdmissionReconciler.run

    assert admission.reload.released_at, "an absence that held the window costs the installation nothing to end"
    assert_equal SessionRuntimeOperation::ABANDONED, op.reload.state,
      "the outcome was never learned, so it is abandoned rather than completed"
    assert_match(/No workload existed/, op.error)
    assert_equal 0, SessionAdmissionReconciler.snapshot[:pinned_reservations]
  end

  # The window measures uninterrupted absence. A pass that finds the workload
  # again has to erase what earlier passes proved, or the window could be
  # assembled out of moments that were never continuous — which is the one way
  # this could hand a live workload's seat to somebody else.
  test "a workload that reappears resets the confirmation clock" do
    session = create(:terminal_session, user: @user, project: @project, state: "cancelled", started_at: 2.hours.ago)
    admission = admit(session)
    session.update!(state: "cancelled", started_at: 2.hours.ago)
    admission.update!(launch_state: "acknowledged", runtime_id: "runtime-id",
                      phase_state: { "cleanup_collected" => true })
    op = admission.session_runtime_operations.create!(phase: "create_container", state: "uncertain")
    op.update!(absent_since: 10.minutes.ago)

    runtime = ContainerRuntime::DockerRuntime.new
    ContainerRuntime.stubs(:build).returns(runtime)
    # Present on the first look, and still present after the delete is accepted:
    # deletion is asynchronous, so this pass proves nothing (AD-6).
    runtime.stubs(:session_absent?).returns(false, false)
    runtime.stubs(:cleanup_session)
    stub_closed_workflow(session.workflow_id)

    SessionAdmissionReconciler.run

    assert_nil admission.reload.released_at
    assert_nil op.reload.absent_since, "a workload that exists invalidates every earlier proof"
    assert_equal "uncertain", op.state
  end

  test "switching the release off leaves the slot pinned for a human" do
    Settings.stubs(:session_admission).returns(Hashie::Mash.new(project_default: 1, pinned_release_enabled: false))
    session = create(:terminal_session, user: @user, project: @project, state: "cancelled", started_at: 2.hours.ago)
    admission = admit(session)
    session.update!(state: "cancelled", started_at: 2.hours.ago)
    admission.update!(launch_state: "acknowledged", runtime_id: "runtime-id",
                      phase_state: { "cleanup_collected" => true })
    op = admission.session_runtime_operations.create!(phase: "create_container", state: "uncertain")
    op.update!(absent_since: 1.hour.ago)

    runtime = ContainerRuntime::DockerRuntime.new
    ContainerRuntime.stubs(:build).returns(runtime)
    runtime.stubs(:session_absent?).returns(true)
    stub_closed_workflow(session.workflow_id)

    SessionAdmissionReconciler.run

    assert_nil admission.reload.released_at
    assert_equal "uncertain", op.reload.state
  end

  # Four days of production evidence: twelve reservations recorded
  # "RPCError: workflow not found" once a minute and were never cleaned up,
  # because the reconciler read Temporal's one definitive negative answer as
  # "unknown" and skipped the admission. A cap of twenty ran four sessions.
  test "a workflow Temporal has no record of releases its reservation" do
    session = create(:terminal_session, user: @user, project: @project, state: "cancelled", started_at: 2.hours.ago)
    admission = admit(session)
    session.update!(state: "cancelled", started_at: 2.hours.ago)
    admission.update!(launch_state: "acknowledged", runtime_id: "runtime-id",
                      phase_state: { "cleanup_collected" => true })
    admission.session_runtime_operations.create!(phase: "exec", state: "uncertain")

    runtime = ContainerRuntime::DockerRuntime.new
    ContainerRuntime.stubs(:build).returns(runtime)
    runtime.stubs(:session_absent?).returns(true)
    stub_missing_workflow(session.workflow_id)

    SessionAdmissionReconciler.run

    assert admission.reload.released_at, "an execution that does not exist can never report a result"
    assert_nil admission.last_error, "the old code recorded this every minute instead of cleaning up"
  end

  # The other edge of reading NOT_FOUND as "closed". A claim commits before the
  # preflight and before the Temporal start, so a launch that is going perfectly
  # spends seconds as `claimed` with no execution to describe yet. This pass
  # reaped those: between 2026-09-05 and 2026-09-18 production failed 69 sessions
  # as "Container workflow ended" within a second or two of `claimed_at`, every
  # one of them on the minute boundary this runs on. They had no `started_at`, no
  # runtime operation and an empty log, because the container they were told had
  # ended was never built.
  test "a launch still inside its claim lease is not reaped" do
    session = create(:terminal_session, user: @user, project: @project)
    admission = admit(session)
    # Exactly what SessionLaunchRelay#dispatch commits before it does any work.
    admission.update!(launch_state: "claimed", claimed_at: Time.current)
    ContainerRuntime.expects(:build).never
    stub_missing_workflow(session.workflow_id)

    SessionAdmissionReconciler.run

    assert_nil admission.reload.released_at, "a dispatcher mid-launch still holds this slot honestly"
    assert_nil admission.stop_requested_at
    refute_equal "failed", session.reload.state
    assert_nil session.error_message
  end

  # And the lease has to end, or `claimed` becomes a state nothing ever cleans
  # up. The relay gets first refusal on an expired claim; what it will not take
  # back — a launch already stopped — is the reaper's.
  test "a claim nobody finished is reconciled once its lease has run out" do
    session = create(:terminal_session, user: @user, project: @project, state: "running", started_at: 1.hour.ago)
    admission = admit(session)
    session.update!(state: "running", started_at: 1.hour.ago)
    admission.update!(launch_state: "claimed", claimed_at: 5.minutes.ago,
                      stop_requested_at: Time.current, runtime_id: nil)

    ContainerRuntime.stubs(:build).returns(ContainerRuntime::DockerRuntime.new)
    stub_missing_workflow(session.workflow_id)

    SessionAdmissionReconciler.run

    assert admission.reload.released_at, "an expired lease must not pin the slot forever"
    assert_equal "failed", session.reload.state
  end

  test "a workflow that is merely unreachable keeps its reservation" do
    session = create(:terminal_session, user: @user, project: @project, state: "running", started_at: 1.hour.ago)
    admission = admit(session)
    session.update!(state: "running", started_at: 1.hour.ago)
    admission.update!(launch_state: "acknowledged")

    ContainerRuntime.expects(:build).never
    stub_failing_workflow(session.workflow_id, Temporalio::Error::RPCError::Code::UNAVAILABLE)

    SessionAdmissionReconciler.run

    # Cleaning up behind a workflow we simply cannot reach would race its own
    # cleanup, so a transport failure has to stay "unknown" (AD-5).
    assert_nil admission.reload.released_at
    assert_match(/RPCError/, admission.last_error)
  end

  test "a run stop marker is fanned out to step runs that missed the cancellation" do
    run = create(:workflow_run, :running)
    step_run = create(:step_run, :running, workflow_run: run)
    run.update!(stop_requested_at: Time.current)

    TemporalService.stubs(:enabled?).returns(false)
    SessionAdmissionReconciler.run

    assert_equal "cancelled", step_run.reload.state
  end

  test "the stale reaper leaves a reservation that is waiting for cluster capacity alone" do
    session = create(:terminal_session, user: @user, project: @project, state: "running", started_at: 2.hours.ago)
    admission = admit(session)
    session.update!(state: "running", started_at: 2.hours.ago)
    admission.update!(wait_reason: "cluster_capacity")
    TemporalService.expects(:cancel_workflow).never

    Activities::Session::CleanupStaleActivity.new.run

    assert_equal "running", session.reload.state
    assert_nil admission.reload.released_at
  end

  test "the stale reaper tears down an admitted session that stopped making progress" do
    session = create(:terminal_session, user: @user, project: @project, state: "running", started_at: 2.hours.ago,
      temporal_workflow_id: "agent-session-x")
    admission = admit(session)
    session.update!(state: "running", started_at: 2.hours.ago)
    admission.update!(wait_reason: nil, launch_state: "acknowledged")
    # Reaping means cancelling the workflow so confirmed cleanup returns the
    # slot — never deleting the runtime behind the reservation's back.
    TemporalService.expects(:cancel_workflow).with(session.workflow_id).returns({ ok: true })

    Activities::Session::CleanupStaleActivity.new.run

    assert_equal "cancelled", session.reload.state
    assert_nil admission.reload.released_at, "cleanup, not the reaper, is what frees capacity"
  end

  test "a session that never started is reaped instead of orphaned forever" do
    lost = create(:terminal_session, user: @user, project: @project, state: "not_started", started_at: nil,
                  created_at: 2.hours.ago, temporal_workflow_id: nil)
    fresh = create(:terminal_session, user: @user, project: @project, state: "not_started", started_at: nil)

    Activities::Session::CleanupStaleActivity.new.run

    assert_equal "failed", lost.reload.state,
      "a launch lost between the commit and Temporal used to sit here forever"
    assert_equal "not_started", fresh.reload.state, "a launch still in flight is not stale"
  end

  test "a queued session is never mistaken for one that failed to start" do
    session = create(:terminal_session, user: @user, project: @project)
    SessionAdmissionService.enqueue!(session)
    session.update_column(:created_at, 2.hours.ago)

    Activities::Session::CleanupStaleActivity.new.run

    assert_equal "queued", session.reload.state, "waiting for a slot is not staleness"
  end

  test "a run whose step is still queued is not stale" do
    run = create(:workflow_run, :running, started_at: 6.hours.ago)
    step_run = create(:step_run, :running, workflow_run: run)
    session = create(:terminal_session, user: run.user, project: run.project, session_type: "workflow_step")
    step_run.update!(terminal_session: session)
    SessionAdmissionService.enqueue!(session)

    Activities::Workflow::CleanupStaleRunsActivity.new.run

    assert_equal "running", run.reload.state
    assert_nil run.stop_requested_at
  end

  test "the queue health snapshot separates waiting from wedged" do
    waiting = create(:terminal_session, user: @user, project: @project)
    admit(waiting)
    blocked = create(:terminal_session, user: @user, project: @project)
    SessionAdmissionService.enqueue!(blocked)
    admission = SessionAdmission.find_by(terminal_session: waiting)
    admission.session_runtime_operations.create!(phase: "create_container", state: "uncertain")

    stats = SessionAdmissionReconciler.snapshot

    assert_equal 1, stats[:queued]
    assert_equal 1, stats[:occupied]
    assert_equal 1, stats[:pools_with_queue]
    assert_equal 1, stats[:uncertain_operations]
    assert_equal 1, stats[:pinned_reservations], "an unaccountable create is what an operator is paged for"
    assert_equal 0, stats[:operations_in_flight], "a provisioning create must not read as pinned capacity"
    assert_operator stats[:oldest_queue_wait_seconds], :>=, 0

    admission.session_runtime_operations.create!(phase: "exec", state: "in_flight")

    stats = SessionAdmissionReconciler.snapshot
    assert_equal 1, stats[:operations_in_flight]
    assert_equal 1, stats[:uncertain_operations]
    # An exec nobody can account for is worth reading — a session died
    # mid-launch — but it costs no capacity, so it must not inflate the alarm.
    assert_equal 1, stats[:pinned_reservations]
  end

  private

  def stub_missing_workflow(workflow_id)
    stub_failing_workflow(workflow_id, Temporalio::Error::RPCError::Code::NOT_FOUND)
  end

  def stub_failing_workflow(workflow_id, code)
    error = Temporalio::Error::RPCError.new(
      "workflow not found for ID: #{workflow_id}", code: code, raw_grpc_status: nil
    )
    handle = mock("workflow handle")
    handle.stubs(:describe).raises(error)
    client = mock("temporal client")
    client.stubs(:workflow_handle).with(workflow_id).returns(handle)
    TemporalService.stubs(:enabled?).returns(true)
    TemporalService.stubs(:client).returns(client)
  end

  def stub_closed_workflow(workflow_id)
    description = Struct.new(:status).new(Temporalio::Client::WorkflowExecutionStatus::COMPLETED)
    handle = mock("workflow handle")
    handle.stubs(:describe).returns(description)
    client = mock("temporal client")
    client.stubs(:workflow_handle).with(workflow_id).returns(handle)
    TemporalService.stubs(:enabled?).returns(true)
    TemporalService.stubs(:client).returns(client)
  end
end
