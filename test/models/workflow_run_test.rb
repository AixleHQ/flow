# frozen_string_literal: true

require "test_helper"

class WorkflowRunTest < ActiveSupport::TestCase
  setup do
    @company = create(:company, name: "wrtest-co-#{SecureRandom.hex(4)}")
    @admin = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @admin, name: "wrtest-proj-#{SecureRandom.hex(4)}")
    @workflow = create(:workflow, scope: @project, name: "wrtest-wf-#{SecureRandom.hex(4)}")
  end

  test "default state is pending" do
    run = create(:workflow_run, project: @project, workflow: @workflow, user: @admin)
    assert_equal "pending", run.state
  end

  test "state transitions: pending -> running -> completed" do
    run = create(:workflow_run, project: @project, workflow: @workflow, user: @admin)
    assert run.may_start?

    run.start!
    assert_equal "running", run.state
    assert_not_nil run.started_at

    run.complete!
    assert_equal "completed", run.state
    assert_not_nil run.completed_at
  end

  test "state transitions: running -> failed" do
    run = create(:workflow_run, :running, project: @project, workflow: @workflow, user: @project.owner)
    run.fail!
    assert_equal "failed", run.state
  end

  test "state transitions: running -> cancelled" do
    run = create(:workflow_run, :running, project: @project, workflow: @workflow, user: @project.owner)
    run.cancel!
    assert_equal "cancelled", run.state
  end

  test "state transitions: running -> paused -> running" do
    run = create(:workflow_run, :running, project: @project, workflow: @workflow, user: @project.owner)
    run.pause!
    assert_equal "paused", run.state

    run.resume!
    assert_equal "running", run.state
  end

  test "cannot transition from pending to completed" do
    run = create(:workflow_run, project: @project, workflow: @workflow, user: @admin)
    assert_not run.may_complete?
  end

  test "can_run_non_interactive? returns true when all steps allow it" do
    step = create(:step, workflow: @workflow, allow_non_interactive: true)
    run = create(:workflow_run, project: @project, workflow: @workflow, user: @admin)
    assert run.can_run_non_interactive?
  end

  test "can_run_non_interactive? returns false when any step requires interaction" do
    create(:step, workflow: @workflow, allow_non_interactive: false)
    run = create(:workflow_run, project: @project, workflow: @workflow, user: @admin)
    assert_not run.can_run_non_interactive?
  end

  test "mode enumerize validates allowed values" do
    run = build(:workflow_run, project: @project, workflow: @workflow, user: @project.owner, mode: "interactive")
    assert run.valid?

    run.mode = "non_interactive"
    assert run.valid?

    run.mode = "mixed"
    assert run.valid?
  end

  test "current_step_run returns latest pending/running step run" do
    run = create(:workflow_run, :running, project: @project, workflow: @workflow, user: @project.owner)
    step = create(:step, workflow: @workflow)
    step_run = create(:step_run, workflow_run: run, step: step, state: "running")

    assert_equal step_run, run.current_step_run
  end

  # --- mark_quota_failed! ---

  test "mark_quota_failed! sets failure_reason and credential FK" do
    run = create(:workflow_run, project: @project, workflow: @workflow, user: @admin)
    credential = create(:agent_credential, user: @admin, agent_type: "claude_code")

    run.mark_quota_failed!(credential_id: credential.id)
    run.reload

    assert_equal "quota_exceeded", run.failure_reason
    assert_equal credential.id, run.failed_agent_credential_id
  end

  test "mark_quota_failed! works with nil credential_id" do
    run = create(:workflow_run, project: @project, workflow: @workflow, user: @admin)

    run.mark_quota_failed!(credential_id: nil)
    run.reload

    assert_equal "quota_exceeded", run.failure_reason
    assert_nil run.failed_agent_credential_id
  end

  # A board card reads the run state, so a run whose step is waiting for a
  # session slot would claim work is happening while nothing is.
  test "waiting_for_slot_ids finds a run whose only step is waiting" do
    run = create(:workflow_run, :running)
    step_run = create(:step_run, :running, workflow_run: run)
    step_run.update!(terminal_session: create(:terminal_session, user: run.user, project: run.project,
                                              session_type: "workflow_step", state: "queued"))

    assert_includes WorkflowRun.waiting_for_slot_ids([ run.id ]), run.id
  end

  test "waiting_for_slot_ids leaves a run that is still executing alone" do
    run = create(:workflow_run, :running)
    working = create(:step_run, :running, workflow_run: run)
    working.update!(terminal_session: create(:terminal_session, user: run.user, project: run.project,
                                             session_type: "workflow_step", state: "ready"))
    waiting = create(:step_run, workflow_run: run)
    waiting.update!(terminal_session: create(:terminal_session, user: run.user, project: run.project,
                                             session_type: "workflow_step", state: "queued"))

    assert_empty WorkflowRun.waiting_for_slot_ids([ run.id ])
  end

  test "waiting_for_slot_ids answers for a whole page in one query" do
    assert_empty WorkflowRun.waiting_for_slot_ids([])
  end
end
