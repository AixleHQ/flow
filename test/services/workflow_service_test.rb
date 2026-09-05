# frozen_string_literal: true

require "test_helper"

class WorkflowServiceTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, owner: @user, company: @company)
    @workflow = create(:workflow, scope: @project)
    @step1 = create(:step, workflow: @workflow, position: 1, name: "Step 1")
    @step2 = create(:step, workflow: @workflow, position: 2, name: "Step 2")
  end

  # == start ==

  test "start creates workflow run with step runs and starts temporal" do
    TemporalWorkflowRegistry.expects(:start_workflow_execution).once

    run = WorkflowService.start(
      workflow: @workflow,
      project: @project,
      user: @user
    )

    assert run.persisted?
    assert_equal @workflow.id, run.workflow_id
    assert_equal @project.id, run.project_id
    assert_equal @user.id, run.user_id
    assert_equal 2, run.step_runs.count
  end

  test "start persists agent_runtime when provided" do
    TemporalWorkflowRegistry.expects(:start_workflow_execution).once

    run = WorkflowService.start(
      workflow: @workflow,
      project: @project,
      user: @user,
      agent_runtime: "claude_code"
    )

    assert run.persisted?
    assert_equal "claude_code", run.agent_runtime
  end

  test "start with task associates board_task" do
    TemporalWorkflowRegistry.expects(:start_workflow_execution).once

    board = create(:board, project: @project)
    column = create(:board_column, board: board)
    task = create(:board_task, board: board, board_column: column)

    run = WorkflowService.start(
      workflow: @workflow,
      project: @project,
      user: @user,
      task: task
    )

    assert run.persisted?
    assert_equal task.id, run.board_task_id
  end

  test "start validates non_interactive mode against step compatibility" do
    @step1.update!(allow_non_interactive: false)

    run = WorkflowService.start(
      workflow: @workflow,
      project: @project,
      user: @user,
      mode: :non_interactive
    )

    assert run.errors[:mode].any?
    assert_not run.persisted?
  end

  # == cancel ==

  test "cancel sends signal and cancels active step runs" do
    TemporalWorkflowRegistry.stubs(:start_workflow_execution)
    run = WorkflowService.start(workflow: @workflow, project: @project, user: @user)
    run.start! if run.may_start?

    TemporalService.expects(:send_signal).with("workflow-execution-#{run.id}", "workflow_cancelled", nil).once

    WorkflowService.cancel(run: run)

    run.reload
    assert_equal "cancelled", run.state
  end

  # The cancellation itself is not the news — the reason is. A session killed by a
  # spend limit or a lost node has one, and the step is where a user sees it.
  test "cancel carries the session's diagnosed reason onto the step run" do
    TemporalWorkflowRegistry.stubs(:start_workflow_execution)
    TemporalService.stubs(:send_signal)
    run = WorkflowService.start(workflow: @workflow, project: @project, user: @user)
    run.start! if run.may_start?
    step_run = run.step_runs.first
    session = create(:terminal_session, user: @user, project: @project,
                                        error_message: "You've hit your individual spend limit")
    step_run.update!(terminal_session: session, state: "running")
    SessionService.stubs(:cancel)

    WorkflowService.cancel(run: run)

    assert_equal "You've hit your individual spend limit", step_run.reload.error_message
  end

  test "cancel leaves the step run unexplained when the generic reason is all there is" do
    TemporalWorkflowRegistry.stubs(:start_workflow_execution)
    TemporalService.stubs(:send_signal)
    run = WorkflowService.start(workflow: @workflow, project: @project, user: @user)
    run.start! if run.may_start?
    step_run = run.step_runs.first
    session = create(:terminal_session, user: @user, project: @project, error_message: "Workflow cancelled")
    step_run.update!(terminal_session: session, state: "running")
    SessionService.stubs(:cancel)

    WorkflowService.cancel(run: run)

    assert_predicate step_run.reload.error_message.to_s, :empty?
  end

  test "cancel records a workflow_cancelled activity on the task's board" do
    TemporalWorkflowRegistry.stubs(:start_workflow_execution)
    TemporalService.stubs(:send_signal)
    board = create(:board, project: @project)
    column = create(:board_column, board: board)
    task = create(:board_task, board: board, board_column: column)
    run = WorkflowService.start(workflow: @workflow, project: @project, user: @user, task: task)

    assert_difference("BoardActivity.count", 1) do
      WorkflowService.cancel(run: run)
    end

    activity = BoardActivity.by_event_type(:workflow_cancelled).sole
    assert_equal task.id, activity.board_task_id
    assert_equal run.id, activity.metadata["workflow_run_id"]
  end

  # == approve_step ==

  test "approve_step marks completed and sends signal" do
    run = create(:workflow_run, workflow: @workflow, project: @project, user: @user, state: "running")
    step_run = create(:step_run, workflow_run: run, step: @step1, state: "running")

    TemporalService.expects(:send_signal).with("workflow-execution-#{run.id}", "step_completed", step_run.id).once

    WorkflowService.approve_step(step_run: step_run)

    step_run.reload
    assert_equal "completed", step_run.state
  end

  # == retry_step ==

  test "retry_step creates new step_run and sends signal when the workflow execution is still open" do
    run = create(:workflow_run, workflow: @workflow, project: @project, user: @user, state: "running")
    step_run = create(:step_run, workflow_run: run, step: @step1, state: "failed", error_message: "Some error")

    TemporalService.stubs(:workflow_open?).with("workflow-execution-#{run.id}").returns(true)
    TemporalService.expects(:send_signal).with(
      "workflow-execution-#{run.id}", "step_retried",
      has_entries("old_step_run_id" => step_run.id, "new_step_run_id" => anything)
    ).once.returns(ok: true)

    result = nil
    assert_difference("StepRun.count", 1) do
      result = WorkflowService.retry_step(step_run: step_run)
    end
    assert result[:ok]

    new_step_run = run.step_runs.where(step: @step1).order(:created_at).last
    assert_equal "pending", new_step_run.state
    assert_not_equal step_run.id, new_step_run.id
  end

  test "retry_step starts a brand-new run reusing the original run's params when the workflow execution has already closed" do
    run = create(:workflow_run, :failed, workflow: @workflow, project: @project, user: @user,
      mode: "interactive", step_overrides: { @step1.id.to_s => { "auto_run" => true } },
      input_asset_ids: [ 7 ], repository_ids: [ 9 ], agent_runtime: "claude_code",
      shared_context: { "requested_model" => "opus" })
    step_run = create(:step_run, workflow_run: run, step: @step1, state: "failed", error_message: "Some error")

    TemporalService.stubs(:workflow_open?).with("workflow-execution-#{run.id}").returns(false)
    TemporalService.expects(:send_signal).never
    TemporalWorkflowRegistry.expects(:start_workflow_execution).once.returns(ok: true)

    result = nil
    assert_difference("WorkflowRun.count", 1) do
      result = WorkflowService.retry_step(step_run: step_run)
    end
    assert result[:ok]

    new_run = result[:run]
    assert new_run.persisted?
    assert_not_equal run.id, new_run.id
    assert_equal @workflow.id, new_run.workflow_id
    assert_equal "interactive", new_run.mode
    assert_equal({ @step1.id.to_s => { "auto_run" => true } }, new_run.step_overrides)
    assert_equal [ 7 ], new_run.input_asset_ids
    assert_equal [ 9 ], new_run.repository_ids
    assert_equal "claude_code", new_run.agent_runtime
    assert_equal "opus", new_run.shared_context["requested_model"]

    # The old failed run is left exactly as it was.
    run.reload
    assert_equal "failed", run.state
    assert_equal "failed", step_run.reload.state
  end

  test "retry_step reuses the original run's board_task on the new run" do
    board = create(:board, project: @project)
    column = create(:board_column, board: board)
    task = create(:board_task, board: board, board_column: column)
    run = create(:workflow_run, :failed, workflow: @workflow, project: @project, user: @user, board_task: task)
    step_run = create(:step_run, workflow_run: run, step: @step1, state: "failed")

    TemporalService.stubs(:workflow_open?).returns(false)
    TemporalWorkflowRegistry.stubs(:start_workflow_execution).returns(ok: true)

    result = WorkflowService.retry_step(step_run: step_run)

    assert_equal task.id, result[:run].board_task_id
  end

  test "retry_step returns an error and creates no run when the new run fails validation" do
    # @step2 doesn't allow_non_interactive and has no override — replaying the
    # original run's non_interactive mode on a fresh start fails WorkflowService
    # .start's validate_mode! before anything is persisted or sent to Temporal.
    run = create(:workflow_run, :failed, workflow: @workflow, project: @project, user: @user, mode: "non_interactive")
    step_run = create(:step_run, workflow_run: run, step: @step1, state: "failed")

    TemporalService.stubs(:workflow_open?).returns(false)
    TemporalWorkflowRegistry.expects(:start_workflow_execution).never

    result = nil
    assert_no_difference("WorkflowRun.count") do
      result = WorkflowService.retry_step(step_run: step_run)
    end
    refute(result[:ok])
  end

  test "retry_step refuses to retry a closed run that isn't failed" do
    run = create(:workflow_run, :cancelled, workflow: @workflow, project: @project, user: @user)
    step_run = create(:step_run, workflow_run: run, step: @step1, state: "failed")

    TemporalService.stubs(:workflow_open?).with("workflow-execution-#{run.id}").returns(false)
    TemporalWorkflowRegistry.expects(:start_workflow_execution).never

    result = nil
    assert_no_difference("WorkflowRun.count") do
      result = WorkflowService.retry_step(step_run: step_run)
    end
    refute(result[:ok])
  end

  test "retry_step discards the new step_run when the signal fails to send" do
    run = create(:workflow_run, workflow: @workflow, project: @project, user: @user, state: "running")
    step_run = create(:step_run, workflow_run: run, step: @step1, state: "failed", error_message: "Some error")

    TemporalService.stubs(:workflow_open?).with("workflow-execution-#{run.id}").returns(true)
    TemporalService.stubs(:send_signal).returns(ok: false, error: "boom")

    result = nil
    assert_no_difference("StepRun.count") do
      result = WorkflowService.retry_step(step_run: step_run)
    end
    refute(result[:ok])
    assert_match(/boom/, result[:error])
  end

  # == skip_step ==

  test "skip_step marks skipped and sends signal" do
    run = create(:workflow_run, workflow: @workflow, project: @project, user: @user, state: "running")
    step_run = create(:step_run, workflow_run: run, step: @step1, state: "running")

    TemporalService.expects(:send_signal).with("workflow-execution-#{run.id}", "step_skipped", step_run.id).once

    WorkflowService.skip_step(step_run: step_run, reason: "Not needed")

    step_run.reload
    assert_equal "skipped", step_run.state
    assert_equal "Not needed", step_run.skip_reason
  end

  # == notify_container_finished ==

  test "notify_container_finished sends signal to workflow execution" do
    run = create(:workflow_run, workflow: @workflow, project: @project, user: @user, state: "running")
    step_run = create(:step_run, workflow_run: run, step: @step1)

    TemporalService.expects(:send_signal).with("workflow-execution-#{run.id}", :container_finished, step_run.id).once

    WorkflowService.notify_container_finished(step_run: step_run)
  end
end
