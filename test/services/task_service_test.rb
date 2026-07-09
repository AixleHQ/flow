# frozen_string_literal: true

require "test_helper"

class TaskServiceTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @company = @user.company
    @project = create(:project, owner: @user, company: @company)
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
  end

  # == create ==

  test "create saves task and records activity" do
    task = TaskService.create(
      board: @board,
      params: { title: "New Task", board_column_id: @column.id },
      actor: @user
    )

    assert task.persisted?
    assert_equal "New Task", task.title
    assert BoardActivity.exists?(board: @board, event_type: :task_created, board_task: task)
  end

  test "create returns invalid task on validation failure" do
    task = TaskService.create(
      board: @board,
      params: { title: nil, board_column_id: @column.id },
      actor: @user
    )

    assert_not task.persisted?
    assert_not BoardActivity.exists?(board: @board, event_type: :task_created)
  end

  test "create checks auto-trigger on column with auto binding" do
    workflow = create(:workflow, scope: @company)
    ColumnWorkflowBinding.create!(board_column: @column, workflow: workflow, trigger_mode: :auto, cooldown_seconds: 0)

    WorkflowService.expects(:start).with(
      has_entries(workflow: workflow, task: anything, mode: :non_interactive)
    ).once

    TaskService.create(
      board: @board,
      params: { title: "Auto Task", board_column_id: @column.id },
      actor: @user
    )
  end

  # == archive / unarchive ==

  test "archive sets archived_at and records activity" do
    task = create(:board_task, board: @board, board_column: @column)

    result = TaskService.archive(task: task, actor: @user)

    assert_predicate result, :archived?
    assert_predicate task.reload, :archived?
    assert BoardActivity.exists?(board: @board, event_type: :task_archived, board_task: task)
  end

  test "archive is a no-op on an already-archived task" do
    task = create(:board_task, board: @board, board_column: @column, archived_at: Time.current)

    TaskService.archive(task: task, actor: @user)

    assert_equal 0, BoardActivity.where(board: @board, event_type: :task_archived, board_task: task).count
  end

  test "unarchive clears archived_at and records activity" do
    task = create(:board_task, board: @board, board_column: @column, archived_at: Time.current)

    result = TaskService.unarchive(task: task, actor: @user)

    assert_not result.archived?
    assert_not task.reload.archived?
    assert BoardActivity.exists?(board: @board, event_type: :task_unarchived, board_task: task)
  end

  test "unarchive is a no-op on an active task" do
    task = create(:board_task, board: @board, board_column: @column)

    TaskService.unarchive(task: task, actor: @user)

    assert_equal 0, BoardActivity.where(board: @board, event_type: :task_unarchived, board_task: task).count
  end

  # == update ==

  test "update saves changes and records activity" do
    task = create(:board_task, board: @board, board_column: @column, title: "Old")

    result = TaskService.update(task: task, params: { title: "New" }, actor: @user)

    assert_equal "New", result.title
    assert BoardActivity.exists?(board: @board, event_type: :task_updated, board_task: task)
  end

  test "update assigns a valid epic parent" do
    epic = create(:board_task, board: @board, board_column: @column, task_type: :epic)
    task = create(:board_task, board: @board, board_column: @column, task_type: :story)

    result = TaskService.update(task: task, params: { parent_task_id: epic.id }, actor: @user)

    assert_empty result.errors
    assert_equal epic.id, task.reload.parent_task_id
  end

  test "update surfaces validation errors and does not record activity on failure" do
    non_epic = create(:board_task, board: @board, board_column: @column, task_type: :bug)
    task = create(:board_task, board: @board, board_column: @column, task_type: :story)

    result = TaskService.update(task: task, params: { parent_task_id: non_epic.id }, actor: @user)

    assert result.errors[:parent_task].present?
    assert_nil task.reload.parent_task_id
    assert_not BoardActivity.exists?(board: @board, event_type: :task_updated, board_task: task)
  end

  # == destroy ==

  test "destroy removes task and records activity" do
    task = create(:board_task, board: @board, board_column: @column)

    assert_difference -> { BoardTask.count }, -1 do
      TaskService.destroy(task: task, actor: @user)
    end

    assert BoardActivity.exists?(board: @board, event_type: :task_deleted)
  end

  # == move ==

  test "move changes column and creates transition" do
    task = create(:board_task, board: @board, board_column: @column, position: 1)
    new_column = create(:board_column, board: @board)

    assert_difference -> { ColumnTransition.count }, 1 do
      TaskService.move(task: task, to_column: new_column, actor: @user)
    end

    task.reload
    assert_equal new_column.id, task.board_column_id
  end

  test "move within same column does not create transition" do
    task = create(:board_task, board: @board, board_column: @column, position: 1)

    assert_no_difference -> { ColumnTransition.count } do
      TaskService.move(task: task, to_column: @column, position: 2, actor: @user)
    end
  end

  test "move to column with auto binding triggers workflow" do
    workflow = create(:workflow, scope: @company)
    new_column = create(:board_column, board: @board)
    ColumnWorkflowBinding.create!(board_column: new_column, workflow: workflow, trigger_mode: :auto, cooldown_seconds: 0)

    task = create(:board_task, board: @board, board_column: @column, position: 1)

    WorkflowService.expects(:start).with(
      has_entries(workflow: workflow, task: task, mode: :non_interactive)
    ).once

    TaskService.move(task: task, to_column: new_column, actor: @user)
  end

  test "move to column with auto binding triggers workflow even when active run exists" do
    prior_workflow = create(:workflow, scope: @company)
    auto_workflow = create(:workflow, scope: @company)
    new_column = create(:board_column, board: @board)
    ColumnWorkflowBinding.create!(board_column: new_column, workflow: auto_workflow, trigger_mode: :auto, cooldown_seconds: 0)

    task = create(:board_task, board: @board, board_column: @column, position: 1)
    create(:workflow_run, workflow: prior_workflow, project: @project, user: @user, board_task: task, state: "running")

    WorkflowService.expects(:start).with(
      has_entries(workflow: auto_workflow, task: task, mode: :non_interactive)
    ).once

    TaskService.move(task: task, to_column: new_column, actor: @user)
  end

  # == trigger_workflow ==

  test "trigger_workflow starts workflow for manual binding" do
    workflow = create(:workflow, scope: @company)
    binding = ColumnWorkflowBinding.create!(board_column: @column, workflow: workflow, trigger_mode: :manual, cooldown_seconds: 0)
    task = create(:board_task, board: @board, board_column: @column)

    WorkflowService.expects(:start).with(
      has_entries(workflow: workflow, task: task, mode: :non_interactive)
    ).returns(build(:workflow_run))

    result = TaskService.trigger_workflow(task: task, binding: binding, actor: @user)
    assert_not result.is_a?(Hash)
  end

  test "trigger_workflow returns error for non-manual binding" do
    binding = nil
    task = create(:board_task, board: @board, board_column: @column)

    result = TaskService.trigger_workflow(task: task, binding: binding, actor: @user)
    assert_equal "No workflow binding on current column", result[:error]
  end

  test "trigger_workflow returns error when active run exists" do
    workflow = create(:workflow, scope: @company)
    binding = ColumnWorkflowBinding.create!(board_column: @column, workflow: workflow, trigger_mode: :manual, cooldown_seconds: 0)
    task = create(:board_task, board: @board, board_column: @column)
    create(:workflow_run, workflow: workflow, project: @project, user: @user, board_task_id: task.id, state: "running")

    result = TaskService.trigger_workflow(task: task, binding: binding, actor: @user)
    assert_equal "Active workflow run already exists for this task", result[:error]
  end

  # == resolve_gate ==

  test "resolve_gate marks gate as resolved with resolution data" do
    task = create(:board_task, board: @board, board_column: @column)
    gate = task.gates.create!(
      gate_type: :github_checks_completed,
      metadata: { repo_full_name: "org/app", pr_number: 1 },
      creator: @user
    )

    TaskService.resolve_gate(gate: gate, resolution_data: { conclusion: "success" })

    gate.reload
    assert gate.resolved?
    assert_equal "success", gate.resolution_data["conclusion"]
    assert_not_nil gate.resolved_at
  end

  test "resolve_gate triggers auto-workflow when all gates resolved" do
    workflow = create(:workflow, scope: @company)
    ColumnWorkflowBinding.create!(board_column: @column, workflow: workflow, trigger_mode: :auto, cooldown_seconds: 0)

    task = create(:board_task, board: @board, board_column: @column, assignee: @user)
    gate = task.gates.create!(
      gate_type: :github_checks_completed,
      metadata: { repo_full_name: "org/app", pr_number: 1 },
      creator: @user
    )

    WorkflowService.expects(:start).with(
      has_entries(workflow: workflow, task: task, mode: :non_interactive)
    ).once

    TaskService.resolve_gate(gate: gate, resolution_data: { conclusion: "success" })
  end

  test "resolve_gate does not trigger auto-workflow when other pending gates remain" do
    workflow = create(:workflow, scope: @company)
    ColumnWorkflowBinding.create!(board_column: @column, workflow: workflow, trigger_mode: :auto, cooldown_seconds: 0)

    task = create(:board_task, board: @board, board_column: @column, assignee: @user)
    gate1 = task.gates.create!(
      gate_type: :github_checks_completed,
      metadata: { repo_full_name: "org/app", pr_number: 1 },
      creator: @user
    )
    task.gates.create!(
      gate_type: :github_checks_completed,
      metadata: { repo_full_name: "org/app", pr_number: 2 },
      creator: @user
    )

    WorkflowService.expects(:start).never

    TaskService.resolve_gate(gate: gate1, resolution_data: { conclusion: "success" })
  end

  test "remove_gate deletes pending gate" do
    task = create(:board_task, board: @board, board_column: @column)
    gate = task.gates.create!(
      gate_type: :github_checks_completed,
      metadata: { repo_full_name: "org/app", pr_number: 1 },
      creator: @user
    )

    assert_difference -> { Gate.count }, -1 do
      TaskService.remove_gate(gate: gate, actor: @user)
    end
  end

  test "remove_gate triggers auto-workflow when it removes the last pending gate" do
    workflow = create(:workflow, scope: @company)
    ColumnWorkflowBinding.create!(board_column: @column, workflow: workflow, trigger_mode: :auto, cooldown_seconds: 0)

    task = create(:board_task, board: @board, board_column: @column, assignee: @user)
    gate = task.gates.create!(
      gate_type: :github_checks_completed,
      metadata: { repo_full_name: "org/app", pr_number: 1 },
      creator: @user
    )

    WorkflowService.expects(:start).with(
      has_entries(workflow: workflow, task: task, mode: :non_interactive)
    ).once

    TaskService.remove_gate(gate: gate, actor: @user)
  end

  # == check_auto_trigger (pending gates guard) ==

  test "check_auto_trigger does not start workflow when task has pending gates" do
    workflow = create(:workflow, scope: @company)
    ColumnWorkflowBinding.create!(board_column: @column, workflow: workflow, trigger_mode: :auto, cooldown_seconds: 0)

    task = create(:board_task, board: @board, board_column: @column, assignee: @user)
    task.gates.create!(
      gate_type: :github_checks_completed,
      metadata: { repo_full_name: "org/app", pr_number: 1 },
      creator: @user
    )

    WorkflowService.expects(:start).never

    TaskService.check_auto_trigger(task: task, column: @column, actor: @user)
  end

  test "check_auto_trigger starts workflow when task has no pending gates" do
    workflow = create(:workflow, scope: @company)
    ColumnWorkflowBinding.create!(board_column: @column, workflow: workflow, trigger_mode: :auto, cooldown_seconds: 0)

    task = create(:board_task, board: @board, board_column: @column, assignee: @user)

    WorkflowService.expects(:start).with(
      has_entries(workflow: workflow, task: task, mode: :non_interactive)
    ).once

    TaskService.check_auto_trigger(task: task, column: @column, actor: @user)
  end

  test "check_auto_trigger does not start workflow when last run failed with quota_exceeded" do
    workflow = create(:workflow, scope: @company)
    ColumnWorkflowBinding.create!(board_column: @column, workflow: workflow, trigger_mode: :auto, cooldown_seconds: 0)
    run = create(:workflow_run, :failed, workflow: workflow, project: @project, user: @user)
    run.update_columns(failure_reason: "quota_exceeded")

    task = create(:board_task, board: @board, board_column: @column, assignee: @user)

    WorkflowService.expects(:start).never

    TaskService.check_auto_trigger(task: task, column: @column, actor: @user)
  end

  test "check_auto_trigger starts workflow when last run has no quota failure" do
    workflow = create(:workflow, scope: @company)
    ColumnWorkflowBinding.create!(board_column: @column, workflow: workflow, trigger_mode: :auto, cooldown_seconds: 0)
    create(:workflow_run, :failed, workflow: workflow, project: @project, user: @user)

    task = create(:board_task, board: @board, board_column: @column, assignee: @user)

    WorkflowService.expects(:start).with(
      has_entries(workflow: workflow, task: task, mode: :non_interactive)
    ).once

    TaskService.check_auto_trigger(task: task, column: @column, actor: @user)
  end
end
