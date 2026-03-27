# frozen_string_literal: true

require "test_helper"

class InternalTools::MetaBoardToolsTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, project: @project, name: "Test Board")
    @col1 = create(:board_column, board: @board, name: "Backlog", position: 1)
    @col2 = create(:board_column, board: @board, name: "In Progress", position: 2)

    builder_workflow = create(:workflow, scope: @company)
    builder_step = create(:step, workflow: builder_workflow)
    @workflow_run = create(:workflow_run, workflow: builder_workflow, project: @project, user: @user)
    @step_run = create(:step_run, workflow_run: @workflow_run, step: builder_step)

    step_run = @step_run
    project = @project
    @session = Object.new
    @session.define_singleton_method(:project) { project }
    @session.define_singleton_method(:step_run) { step_run }
  end

  # ── meta_get_board ──

  test "meta_get_board returns board with columns" do
    result = InternalTools::MetaGetBoard.new(params: {}, session: @session).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal @board.id, data["board_id"]
    assert_equal 2, data["columns_count"]
    assert_equal "Backlog", data["columns"][0]["name"]
  end

  test "meta_get_board shows workflow bindings" do
    wf = create(:workflow, scope: @project, name: "Review Bot")
    ColumnWorkflowBinding.create!(board_column: @col2, workflow: wf, trigger_mode: :auto)

    result = InternalTools::MetaGetBoard.new(params: {}, session: @session).execute

    data = JSON.parse(result[:stdout])
    col2_data = data["columns"].find { |c| c["name"] == "In Progress" }
    assert_not_nil col2_data["workflow_binding"]
    assert_equal "auto", col2_data["workflow_binding"]["trigger_mode"]
    assert_equal "Review Bot", col2_data["workflow_binding"]["workflow_name"]
  end

  # ── meta_create_board_column ──

  test "meta_create_board_column creates column" do
    result = InternalTools::MetaCreateBoardColumn.new(
      params: { name: "Done", purpose: "Completed tasks" },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal "Done", data["name"]
    assert_equal "Completed tasks", data["purpose"]
    assert_equal 3, data["position"] # auto-assigned after existing 2
  end

  test "meta_create_board_column with explicit position" do
    result = InternalTools::MetaCreateBoardColumn.new(
      params: { name: "Review", position: 10 },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal "Review", data["name"]
    assert_equal 10, data["position"]
  end

  # ── meta_update_board_column ──

  test "meta_update_board_column updates name and purpose" do
    result = InternalTools::MetaUpdateBoardColumn.new(
      params: { column_id: @col1.id, name: "Todo", purpose: "New purpose" },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    @col1.reload
    assert_equal "Todo", @col1.name
    assert_equal "New purpose", @col1.purpose
  end

  # ── meta_delete_board_column ──

  test "meta_delete_board_column deletes empty column" do
    result = InternalTools::MetaDeleteBoardColumn.new(
      params: { column_id: @col2.id },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    assert_nil BoardColumn.find_by(id: @col2.id)
  end

  test "meta_delete_board_column fails if column has tasks" do
    create(:board_task, board: @board, board_column: @col1, title: "Task 1")

    result = InternalTools::MetaDeleteBoardColumn.new(
      params: { column_id: @col1.id },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "has"
    assert_includes result[:stderr], "tasks"
  end

  # ── meta_create_column_binding ──

  test "meta_create_column_binding binds workflow to column" do
    wf = create(:workflow, scope: @project, name: "Auto Review")

    result = InternalTools::MetaCreateColumnBinding.new(
      params: { column_id: @col1.id, workflow_id: wf.id, trigger_mode: "auto", cooldown_seconds: 10 },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal "auto", data["trigger_mode"]
    assert_equal 10, data["cooldown_seconds"]
    assert_equal "Auto Review", data["workflow_name"]
  end

  test "meta_create_column_binding fails if column already has binding" do
    wf1 = create(:workflow, scope: @project, name: "WF1")
    wf2 = create(:workflow, scope: @project, name: "WF2")
    ColumnWorkflowBinding.create!(board_column: @col1, workflow: wf1, trigger_mode: :manual)

    result = InternalTools::MetaCreateColumnBinding.new(
      params: { column_id: @col1.id, workflow_id: wf2.id },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "already has a binding"
  end

  # ── meta_delete_column_binding ──

  test "meta_delete_column_binding removes binding" do
    wf = create(:workflow, scope: @project)
    binding = ColumnWorkflowBinding.create!(board_column: @col1, workflow: wf, trigger_mode: :manual)

    result = InternalTools::MetaDeleteColumnBinding.new(
      params: { binding_id: binding.id },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    assert_nil ColumnWorkflowBinding.find_by(id: binding.id)
  end

  # ── meta_setup_board_from_preset ──

  test "meta_setup_board_from_preset creates board from preset" do
    # Remove existing board first (setup creates one)
    @board.board_columns.destroy_all
    @board.destroy!

    result = InternalTools::MetaSetupBoardFromPreset.new(
      params: { preset: "dev_team" },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal "dev_team", data["preset"]
    assert_equal 7, data["columns"].size
    assert_equal "Backlog", data["columns"][0]["name"]
  end

  test "meta_setup_board_from_preset fails with invalid preset" do
    result = InternalTools::MetaSetupBoardFromPreset.new(
      params: { preset: "nonexistent" },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "Invalid preset"
  end
end
