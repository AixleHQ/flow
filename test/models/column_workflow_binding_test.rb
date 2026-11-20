# frozen_string_literal: true

require "test_helper"

class ColumnWorkflowBindingTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, owner: @user, company: @company)
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    @workflow = create(:workflow, scope: @project)
  end

  test "records who created the trigger" do
    binding = ColumnWorkflowBinding.create!(board_column: @column, workflow: @workflow, created_by: @user)

    assert_equal @user, binding.created_by
  end

  test "a trigger whose creator is deleted survives without one" do
    creator = create(:user, company: @company)
    binding = ColumnWorkflowBinding.create!(board_column: @column, workflow: @workflow, created_by: creator)

    creator.destroy!

    assert ColumnWorkflowBinding.exists?(binding.id)
    assert_nil binding.reload.created_by_id
  end

  test "an auto trigger refuses a workflow with a step that waits for a person, and names the step" do
    create(:step, workflow: @workflow, name: "Plan", allow_non_interactive: true)
    create(:step, workflow: @workflow, name: "Review by hand")
    binding = ColumnWorkflowBinding.new(board_column: @column, workflow: @workflow, trigger_mode: :auto)

    assert_not binding.valid?
    assert_equal [ "Workflow can't start on its own when a card enters the column — turn on auto-run for " \
                   "these steps or make the trigger manual: Review by hand" ], binding.errors.full_messages
  end

  test "a manual trigger takes such a workflow, and an auto one takes it once every step runs on its own" do
    step = create(:step, workflow: @workflow, name: "Review by hand")
    binding = ColumnWorkflowBinding.create!(board_column: @column, workflow: @workflow, trigger_mode: :manual)

    assert_raises(ActiveRecord::RecordInvalid) { binding.update!(trigger_mode: :auto) }

    step.update!(allow_non_interactive: true)
    binding.update!(trigger_mode: :auto)
    assert_equal "auto", binding.reload.trigger_mode
  end

  test "a trigger created before creators were recorded stays valid" do
    binding = ColumnWorkflowBinding.new(board_column: @column, workflow: @workflow)

    assert binding.valid?, binding.errors.full_messages.to_sentence
  end
end
