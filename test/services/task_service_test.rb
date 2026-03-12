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

  # == update ==

  test "update saves changes and records activity" do
    task = create(:board_task, board: @board, board_column: @column, title: "Old")

    result = TaskService.update(task: task, params: { title: "New" }, actor: @user)

    assert_equal "New", result.title
    assert BoardActivity.exists?(board: @board, event_type: :task_updated, board_task: task)
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
    assert_equal "No manual workflow binding on current column", result[:error]
  end

  test "trigger_workflow returns error when active run exists" do
    workflow = create(:workflow, scope: @company)
    binding = ColumnWorkflowBinding.create!(board_column: @column, workflow: workflow, trigger_mode: :manual, cooldown_seconds: 0)
    task = create(:board_task, board: @board, board_column: @column)
    create(:workflow_run, workflow: workflow, project: @project, user: @user, board_task_id: task.id, state: "running")

    result = TaskService.trigger_workflow(task: task, binding: binding, actor: @user)
    assert_equal "Active workflow run already exists for this task", result[:error]
  end
end
