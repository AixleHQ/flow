# frozen_string_literal: true

require "test_helper"

class WorkflowRunRelayTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, owner: @user, company: @company)
    @workflow = create(:workflow, scope: @project)
    # The relay only ever runs inside the Temporal worker, so a failed dispatch is
    # a real failure there — never the "Temporal is switched off" case.
    TemporalService.stubs(:enabled?).returns(true)
  end

  # A run as WorkflowService.start leaves it when the Temporal RPC never landed:
  # committed, enrolled in the outbox, and executed by nobody.
  def undispatched_run(created_at: 5.minutes.ago, attempts: 1, **attrs)
    create(:workflow_run,
      workflow: @workflow, project: @project, user: @user,
      state: "pending", relay_state: "pending", relay_attempts: attempts,
      created_at: created_at, **attrs)
  end

  test "drain re-dispatches a run stranded past the grace window" do
    run = undispatched_run
    TemporalWorkflowRegistry.expects(:start_workflow_execution).once.returns(ok: true)

    result = WorkflowRunRelay.drain

    assert_equal 1, result[:swept]
    assert_equal 1, result[:dispatched]
    assert_equal 0, result[:failed]
    assert_equal "dispatched", run.reload.relay_state
    assert_equal 2, run.relay_attempts
  end

  test "drain leaves a fresh run alone until the grace window passes" do
    run = undispatched_run(created_at: Time.current)
    TemporalWorkflowRegistry.expects(:start_workflow_execution).never

    result = WorkflowRunRelay.drain

    assert_equal 0, result[:swept]
    assert_equal "pending", run.reload.relay_state
  end

  test "drain ignores runs whose dispatch was already confirmed" do
    undispatched_run(relay_state: "dispatched")
    TemporalWorkflowRegistry.expects(:start_workflow_execution).never

    assert_equal 0, WorkflowRunRelay.drain[:swept]
  end

  # The worker moved the run on, so the execution plainly exists — whatever our
  # inline call did or did not hear back.
  test "drain ignores a run the worker has already started" do
    undispatched_run(state: "running")
    TemporalWorkflowRegistry.expects(:start_workflow_execution).never

    assert_equal 0, WorkflowRunRelay.drain[:swept]
  end

  test "drain never starts an execution for a run that was cancelled while undispatched" do
    run = undispatched_run(stop_requested_at: Time.current)
    TemporalWorkflowRegistry.expects(:start_workflow_execution).never

    assert_equal 0, WorkflowRunRelay.drain[:swept]
    assert_equal "pending", run.reload.relay_state
  end

  test "drain counts a still-failing dispatch and leaves the run for the next sweep" do
    run = undispatched_run
    TemporalWorkflowRegistry.expects(:start_workflow_execution).once.returns(ok: false, error: "unavailable")

    result = WorkflowRunRelay.drain

    assert_equal 1, result[:swept]
    assert_equal 0, result[:dispatched]
    assert_equal 1, result[:failed]
    assert_equal "pending", run.reload.relay_state
    assert_equal 2, run.relay_attempts
    assert_match(/unavailable/, run.relay_error)
  end

  # One run that can never start must not consume every sweep forever.
  test "drain abandons a run past the attempt ceiling" do
    undispatched_run(attempts: WorkflowRun::RELAY_MAX_ATTEMPTS)
    TemporalWorkflowRegistry.expects(:start_workflow_execution).never

    assert_equal 0, WorkflowRunRelay.drain[:swept]
  end

  test "drain does a bounded amount of work per sweep" do
    3.times { undispatched_run }
    TemporalWorkflowRegistry.expects(:start_workflow_execution).twice.returns(ok: true)

    assert_equal 2, WorkflowRunRelay.drain(limit: 2)[:swept]
  end

  test "a failing run keeps its place in line rather than blocking the ones behind it" do
    poison = undispatched_run(created_at: 10.minutes.ago)
    healthy = undispatched_run(created_at: 5.minutes.ago)
    TemporalWorkflowRegistry.stubs(:start_workflow_execution).returns(ok: false, error: "unavailable").then.returns(ok: true)

    result = WorkflowRunRelay.drain

    assert_equal 2, result[:swept]
    assert_equal 1, result[:dispatched]
    assert_equal "pending", poison.reload.relay_state
    assert_equal "dispatched", healthy.reload.relay_state
  end
end
