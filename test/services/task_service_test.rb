# frozen_string_literal: true

require "test_helper"

class TaskServiceTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, owner: @user, company: @company)
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
  end

  # A candidate assignee has to clear BoardTask#assignee_is_project_member, so
  # company membership alone is not enough — the project must reach them too.
  # `credential:` mirrors having connected an agent: without one, a run they own
  # would launch a container with nothing to authenticate as.
  def project_member(role: :employee, credential: true)
    user = create(:user)
    create(:company_membership, user: user, company: @company, role: role)
    create(:project_collaborator, project: @project, user: user)
    create(:agent_credential, user: user, company: @company) if credential
    user
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
    workflow = create(:workflow, scope: @project)
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
    workflow = create(:workflow, scope: @project)
    new_column = create(:board_column, board: @board)
    ColumnWorkflowBinding.create!(board_column: new_column, workflow: workflow, trigger_mode: :auto, cooldown_seconds: 0)

    task = create(:board_task, board: @board, board_column: @column, position: 1)

    WorkflowService.expects(:start).with(
      has_entries(workflow: workflow, task: task, mode: :non_interactive)
    ).once

    TaskService.move(task: task, to_column: new_column, actor: @user)
  end

  test "move to column with auto binding triggers workflow even when active run exists" do
    prior_workflow = create(:workflow, scope: @project)
    auto_workflow = create(:workflow, scope: @project)
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
    workflow = create(:workflow, scope: @project)
    binding = ColumnWorkflowBinding.create!(board_column: @column, workflow: workflow, trigger_mode: :manual, cooldown_seconds: 0)
    task = create(:board_task, board: @board, board_column: @column)

    WorkflowService.expects(:start).with(
      has_entries(workflow: workflow, task: task, mode: :non_interactive)
    ).returns(build(:workflow_run))

    result = TaskService.trigger_workflow(task: task, binding: binding, actor: @user)
    assert_not result.is_a?(Hash)
  end

  # == who a launched run belongs to ==
  #
  # run.user is what the run SPENDS (SessionService.create_for_workflow_step reads
  # it for the credential, the runtime and the model), so these assert on the
  # `user:` WorkflowService.start receives.

  test "trigger_workflow gives the run to the task's assignee, not to whoever pressed Run" do
    assignee = project_member
    workflow = create(:workflow, scope: @project)
    binding = ColumnWorkflowBinding.create!(board_column: @column, workflow: workflow, trigger_mode: :manual, cooldown_seconds: 0)
    task = create(:board_task, board: @board, board_column: @column, assignee: assignee)

    WorkflowService.expects(:start).with(has_entries(user: assignee)).returns(build(:workflow_run))

    TaskService.trigger_workflow(task: task, binding: binding, actor: @user)
  end

  test "trigger_workflow records who asked, even when the run belongs to the assignee" do
    assignee = project_member
    workflow = create(:workflow, scope: @project)
    binding = ColumnWorkflowBinding.create!(board_column: @column, workflow: workflow, trigger_mode: :manual, cooldown_seconds: 0)
    task = create(:board_task, board: @board, board_column: @column, assignee: assignee)
    WorkflowService.stubs(:start).returns(build(:workflow_run))

    TaskService.trigger_workflow(task: task, binding: binding, actor: @user)

    event = TriggerEvent.where(board_task_id: task.id).order(:created_at).last
    assert_equal assignee.id, event.actor_id
    assert_equal @user.id, event.data["requested_by_id"]
  end

  test "trigger_workflow falls back to the requester on an unassigned task" do
    workflow = create(:workflow, scope: @project)
    binding = ColumnWorkflowBinding.create!(board_column: @column, workflow: workflow, trigger_mode: :manual, cooldown_seconds: 0)
    task = create(:board_task, board: @board, board_column: @column)

    WorkflowService.expects(:start).with(has_entries(user: @user)).returns(build(:workflow_run))

    TaskService.trigger_workflow(task: task, binding: binding, actor: @user)
  end

  test "trigger_workflow skips an assignee who cannot own runs" do
    viewer = project_member(role: :viewer)
    workflow = create(:workflow, scope: @project)
    binding = ColumnWorkflowBinding.create!(board_column: @column, workflow: workflow, trigger_mode: :manual, cooldown_seconds: 0)
    task = create(:board_task, board: @board, board_column: @column, assignee: viewer)

    # A viewer cannot launch a session at all, so a run must never be attributed
    # to one — it would be work they could not have started themselves.
    WorkflowService.expects(:start).with(has_entries(user: @user)).returns(build(:workflow_run))

    TaskService.trigger_workflow(task: task, binding: binding, actor: @user)
  end

  test "trigger_workflow skips an assignee who has never connected an agent" do
    unconnected = project_member(credential: false)
    workflow = create(:workflow, scope: @project)
    binding = ColumnWorkflowBinding.create!(board_column: @column, workflow: workflow, trigger_mode: :manual, cooldown_seconds: 0)
    task = create(:board_task, board: @board, board_column: @column, assignee: unconnected)

    # Otherwise the fix trades a run on the wrong account for one that dies with
    # "not logged in": a nil credential is silently skipped downstream, never raised.
    WorkflowService.expects(:start).with(has_entries(user: @user)).returns(build(:workflow_run))

    TaskService.trigger_workflow(task: task, binding: binding, actor: @user)
  end

  test "trigger_workflow skips an assignee whose membership was revoked" do
    former = project_member
    workflow = create(:workflow, scope: @project)
    binding = ColumnWorkflowBinding.create!(board_column: @column, workflow: workflow, trigger_mode: :manual, cooldown_seconds: 0)
    task = create(:board_task, board: @board, board_column: @column, assignee: former)
    former.company_memberships.find_by(company: @company).update!(state: "revoked")

    WorkflowService.expects(:start).with(has_entries(user: @user)).returns(build(:workflow_run))

    TaskService.trigger_workflow(task: task, binding: binding, actor: @user)
  end

  test "an auto-trigger from a card move also belongs to the assignee, not the mover" do
    assignee = project_member
    workflow = create(:workflow, scope: @project)
    auto_column = create(:board_column, board: @board)
    ColumnWorkflowBinding.create!(board_column: auto_column, workflow: workflow, trigger_mode: :auto, cooldown_seconds: 0)
    task = create(:board_task, board: @board, board_column: @column, assignee: assignee)

    WorkflowService.expects(:start).with(has_entries(user: assignee)).returns(build(:workflow_run))

    TaskService.move(task: task, to_column: auto_column, actor: @user)
  end

  test "trigger_workflow returns error for non-manual binding" do
    binding = nil
    task = create(:board_task, board: @board, board_column: @column)

    result = TaskService.trigger_workflow(task: task, binding: binding, actor: @user)
    assert_equal "No workflow binding on current column", result[:error]
  end

  test "trigger_workflow returns error when active run exists" do
    workflow = create(:workflow, scope: @project)
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
    workflow = create(:workflow, scope: @project)
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
    workflow = create(:workflow, scope: @project)
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

  # == mark_gate_stale ==

  test "mark_gate_stale ends the wait with a reason but never with a passing verdict" do
    task = create(:board_task, board: @board, board_column: @column)
    gate = task.gates.create!(
      gate_type: :github_checks_completed,
      metadata: { repo_full_name: "org/app", pr_number: 1 },
      creator: @user
    )

    TaskService.mark_gate_stale(gate: gate, reason: "PR #1 cannot be read", detail: "404 Not Found")

    gate.reload
    assert gate.stale?
    assert_equal "stale", gate.ci_status
    assert_equal "PR #1 cannot be read", gate.diagnostic_reason
    assert_equal "stale", gate.resolution_data["outcome"]
    assert_equal "404 Not Found", gate.resolution_data["detail"]
    assert_nil gate.conclusion
    assert_nil gate.resolved_at
    assert_not gate.passed?
  end

  test "mark_gate_stale records the escalation on the board activity feed" do
    task = create(:board_task, board: @board, board_column: @column)
    gate = task.gates.create!(
      gate_type: :github_checks_completed,
      metadata: { repo_full_name: "org/app", pr_number: 1 },
      creator: @user
    )

    TaskService.mark_gate_stale(gate: gate, reason: "no CI result after 13 hours")

    activity = BoardActivity.where(event_type: "gate_stale", board_task: task).last
    assert_not_nil activity
    assert_equal "system", activity.actor_type
    assert_equal gate.id, activity.metadata["gate_id"]
  end

  test "mark_gate_stale releases the auto-trigger the gate was holding" do
    workflow = create(:workflow, scope: @project)
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

    TaskService.mark_gate_stale(gate: gate, reason: "run deleted")
  end

  test "mark_gate_stale leaves the auto-trigger held while another gate is pending" do
    workflow = create(:workflow, scope: @project)
    ColumnWorkflowBinding.create!(board_column: @column, workflow: workflow, trigger_mode: :auto, cooldown_seconds: 0)

    task = create(:board_task, board: @board, board_column: @column, assignee: @user)
    gate = task.gates.create!(
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

    TaskService.mark_gate_stale(gate: gate, reason: "run deleted")
  end

  test "resolve_gate_by_reconciliation resolves the gate and records the activity" do
    task = create(:board_task, board: @board, board_column: @column)
    gate = task.gates.create!(
      gate_type: :github_checks_completed,
      metadata: { repo_full_name: "org/app", pr_number: 1 },
      creator: @user
    )

    TaskService.resolve_gate_by_reconciliation(
      gate: gate,
      resolution_data: { "conclusion" => "failure", "source" => "reconciliation" }
    )

    gate.reload
    assert gate.resolved?
    assert_equal "failure", gate.conclusion
    assert_equal "failed", gate.ci_status
    activity = BoardActivity.where(event_type: "gate_reconciled", board_task: task).last
    assert_not_nil activity
    assert_equal "failure", activity.metadata["conclusion"]
  end

  # == gate transitions are compare-and-set ==
  #
  # A CI gate has three racing writers: its webhook delivery, the reconciliation
  # sweep, and a retried/overlapping second sweeper. Every terminal transition
  # re-reads `pending` under a row lock, so the first writer wins outright and the
  # losers are no-ops — no overwritten verdict, no duplicate activity row, no
  # second auto-trigger dispatch.

  test "resolve_gate is a no-op on an already resolved gate instead of overwriting its verdict" do
    task = create(:board_task, board: @board, board_column: @column)
    gate = task.gates.create!(
      gate_type: :github_checks_completed,
      metadata: { repo_full_name: "org/app", pr_number: 1 },
      creator: @user
    )

    assert TaskService.resolve_gate(gate: gate, resolution_data: { conclusion: "failure" })
    resolved_at = gate.reload.resolved_at

    assert_not TaskService.resolve_gate(gate: gate, resolution_data: { conclusion: "success" })

    gate.reload
    assert_equal "failure", gate.conclusion
    assert_equal resolved_at.to_i, gate.resolved_at.to_i
  end

  test "resolve_gate dispatches the auto-trigger once when the same gate is resolved twice" do
    workflow = create(:workflow, scope: @project)
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
    TaskService.resolve_gate(gate: gate, resolution_data: { conclusion: "success" })
  end

  test "mark_gate_stale refuses to replace a provider verdict with 'we do not know'" do
    task = create(:board_task, board: @board, board_column: @column)
    gate = task.gates.create!(
      gate_type: :github_checks_completed,
      metadata: { repo_full_name: "org/app", pr_number: 1 },
      creator: @user
    )
    TaskService.resolve_gate(gate: gate, resolution_data: { conclusion: "failure" })

    assert_no_difference -> { BoardActivity.where(event_type: "gate_stale").count } do
      assert_not TaskService.mark_gate_stale(gate: gate, reason: "no CI result after 13 hours")
    end

    gate.reload
    assert gate.resolved?
    assert_equal "failed", gate.ci_status
    assert_equal "failure", gate.conclusion
    assert_nil gate.diagnostic_reason
  end

  test "resolve_gate_by_reconciliation records no second activity when the webhook already won" do
    task = create(:board_task, board: @board, board_column: @column)
    gate = task.gates.create!(
      gate_type: :github_checks_completed,
      metadata: { repo_full_name: "org/app", pr_number: 1 },
      creator: @user
    )
    TaskService.resolve_gate(gate: gate, resolution_data: { conclusion: "failure" })

    assert_no_difference -> { BoardActivity.where(event_type: "gate_reconciled").count } do
      assert_not TaskService.resolve_gate_by_reconciliation(
        gate: gate,
        resolution_data: { "conclusion" => "success", "source" => "reconciliation" }
      )
    end

    assert_equal "failure", gate.reload.conclusion
  end

  test "mark_gate_stale treats a gate deleted from under it as a lost race, not an error" do
    task = create(:board_task, board: @board, board_column: @column)
    gate = task.gates.create!(
      gate_type: :github_checks_completed,
      metadata: { repo_full_name: "org/app", pr_number: 1 },
      creator: @user
    )
    Gate.where(id: gate.id).delete_all

    assert_not TaskService.mark_gate_stale(gate: gate, reason: "run deleted")
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
    workflow = create(:workflow, scope: @project)
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
    workflow = create(:workflow, scope: @project)
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
    workflow = create(:workflow, scope: @project)
    ColumnWorkflowBinding.create!(board_column: @column, workflow: workflow, trigger_mode: :auto, cooldown_seconds: 0)

    task = create(:board_task, board: @board, board_column: @column, assignee: @user)

    WorkflowService.expects(:start).with(
      has_entries(workflow: workflow, task: task, mode: :non_interactive)
    ).once

    TaskService.check_auto_trigger(task: task, column: @column, actor: @user)
  end

  test "check_auto_trigger does not start workflow when last run failed with quota_exceeded" do
    workflow = create(:workflow, scope: @project)
    ColumnWorkflowBinding.create!(board_column: @column, workflow: workflow, trigger_mode: :auto, cooldown_seconds: 0)
    run = create(:workflow_run, :failed, workflow: workflow, project: @project, user: @user)
    run.update_columns(failure_reason: "quota_exceeded")

    task = create(:board_task, board: @board, board_column: @column, assignee: @user)

    WorkflowService.expects(:start).never

    TaskService.check_auto_trigger(task: task, column: @column, actor: @user)
  end

  test "check_auto_trigger starts workflow when last run has no quota failure" do
    workflow = create(:workflow, scope: @project)
    ColumnWorkflowBinding.create!(board_column: @column, workflow: workflow, trigger_mode: :auto, cooldown_seconds: 0)
    create(:workflow_run, :failed, workflow: workflow, project: @project, user: @user)

    task = create(:board_task, board: @board, board_column: @column, assignee: @user)

    WorkflowService.expects(:start).with(
      has_entries(workflow: workflow, task: task, mode: :non_interactive)
    ).once

    TaskService.check_auto_trigger(task: task, column: @column, actor: @user)
  end
end
