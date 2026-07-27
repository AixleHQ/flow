# frozen_string_literal: true

require "test_helper"

class WorkflowServiceTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @company = @user.company
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

  test "retry_step creates new step_run and sends signal" do
    run = create(:workflow_run, workflow: @workflow, project: @project, user: @user, state: "running")
    step_run = create(:step_run, workflow_run: run, step: @step1, state: "failed", error_message: "Some error")

    TemporalService.expects(:send_signal).with(
      "workflow-execution-#{run.id}", "step_retried",
      has_entries("old_step_run_id" => step_run.id, "new_step_run_id" => anything)
    ).once

    assert_difference("StepRun.count", 1) do
      WorkflowService.retry_step(step_run: step_run)
    end

    new_step_run = run.step_runs.where(step: @step1).order(:created_at).last
    assert_equal "pending", new_step_run.state
    assert_not_equal step_run.id, new_step_run.id
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
