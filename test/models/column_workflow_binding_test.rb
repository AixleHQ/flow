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

  test "a trigger created before creators were recorded stays valid" do
    binding = ColumnWorkflowBinding.new(board_column: @column, workflow: @workflow)

    assert binding.valid?, binding.errors.full_messages.to_sentence
  end
end
