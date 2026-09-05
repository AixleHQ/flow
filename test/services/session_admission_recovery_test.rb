# frozen_string_literal: true

require "test_helper"

# Recovery is the half of the queue nobody exercises by hand: a reservation is
# only safe to hold forever if something eventually proves the runtime is gone,
# and only safe to reap if something proves it is not merely waiting.
class SessionAdmissionRecoveryTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    SessionAdmissionPolicy.sync!(installation_limit: 1)
  end

  def admit(session)
    admission = SessionAdmissionService.enqueue!(session)
    SessionAdmissionService.drain!
    admission.reload
  end

  test "a closed container workflow releases the reservation it left behind" do
    session = create(:terminal_session, user: @user, state: "running", started_at: 1.hour.ago)
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
    session = create(:terminal_session, user: @user, state: "running", started_at: 1.hour.ago)
    admission = admit(session)
    session.update!(state: "running", started_at: 1.hour.ago)
    admission.update!(launch_state: "acknowledged")
    admission.session_runtime_operations.create!(phase: "create_container", state: "uncertain")

    TemporalService.expects(:client).never
    SessionAdmissionReconciler.run

    assert_nil admission.reload.released_at
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
    session = create(:terminal_session, user: @user, state: "running", started_at: 2.hours.ago)
    admission = admit(session)
    session.update!(state: "running", started_at: 2.hours.ago)
    admission.update!(wait_reason: "cluster_capacity")
    TemporalService.expects(:cancel_workflow).never

    Activities::Session::CleanupStaleActivity.new.run

    assert_equal "running", session.reload.state
    assert_nil admission.reload.released_at
  end

  test "the stale reaper tears down an admitted session that stopped making progress" do
    session = create(:terminal_session, user: @user, state: "running", started_at: 2.hours.ago,
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
    waiting = create(:terminal_session, user: @user)
    admit(waiting)
    blocked = create(:terminal_session, user: @user)
    SessionAdmissionService.enqueue!(blocked)
    SessionAdmission.find_by(terminal_session: waiting)
                    .session_runtime_operations.create!(phase: "create_container", state: "uncertain")

    stats = SessionAdmissionReconciler.snapshot

    assert_equal 1, stats[:queued]
    assert_equal 1, stats[:occupied]
    assert_equal 1, stats[:pools_with_queue]
    assert_equal 1, stats[:uncertain_operations]
    assert_operator stats[:oldest_queue_wait_seconds], :>=, 0
  end

  private

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
