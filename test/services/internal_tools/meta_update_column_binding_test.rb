# frozen_string_literal: true

require "test_helper"

class InternalTools::MetaUpdateColumnBindingTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, project: @project, name: "Test Board")
    @column = create(:board_column, board: @board, name: "In Progress", position: 1)
    @workflow = create(:workflow, scope: @project, name: "Review Bot")
    @binding = ColumnWorkflowBinding.create!(
      board_column: @column,
      workflow: @workflow,
      trigger_mode: :manual,
      cooldown_seconds: 5
    )

    # A builder workflow context (simulating Aixle Builder running), mirroring
    # the fake session used across the other meta-tool tests.
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

  test "updates trigger_mode and leaves cooldown untouched" do
    result = InternalTools::MetaUpdateColumnBinding.new(
      params: { binding_id: @binding.id, trigger_mode: "auto" },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal @binding.id, data["id"]
    assert_equal "auto", data["trigger_mode"]
    assert_equal 5, data["cooldown_seconds"]

    @binding.reload
    assert @binding.trigger_mode.auto?
    assert_equal 5, @binding.cooldown_seconds
  end

  test "updates cooldown_seconds and leaves trigger_mode untouched" do
    result = InternalTools::MetaUpdateColumnBinding.new(
      params: { binding_id: @binding.id, cooldown_seconds: 300 },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal @binding.id, data["id"]
    assert_equal 300, data["cooldown_seconds"]
    assert_equal "manual", data["trigger_mode"]

    @binding.reload
    assert_equal 300, @binding.cooldown_seconds
    assert @binding.trigger_mode.manual?
  end

  test "updates both trigger_mode and cooldown_seconds together" do
    result = InternalTools::MetaUpdateColumnBinding.new(
      params: { binding_id: @binding.id, trigger_mode: "auto", cooldown_seconds: 120 },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal "auto", data["trigger_mode"]
    assert_equal 120, data["cooldown_seconds"]

    @binding.reload
    assert @binding.trigger_mode.auto?
    assert_equal 120, @binding.cooldown_seconds
  end

  test "no attribute params leaves the binding unchanged and still succeeds" do
    result = InternalTools::MetaUpdateColumnBinding.new(
      params: { binding_id: @binding.id },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal @binding.id, data["id"]
    assert_equal "manual", data["trigger_mode"]
    assert_equal 5, data["cooldown_seconds"]

    @binding.reload
    assert @binding.trigger_mode.manual?
    assert_equal 5, @binding.cooldown_seconds
  end
end
