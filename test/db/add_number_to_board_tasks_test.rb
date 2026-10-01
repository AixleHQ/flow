# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20260930120000_add_number_to_board_tasks")

# The schema already carries the column, so the backfill is exercised on its own:
# numbers are scrambled to what an unmigrated row cannot tell apart, then derived again.
class AddNumberToBoardTasksTest < ActiveSupport::TestCase
  setup do
    company = create(:company)
    owner = create(:user, company: company)
    @board = create(:board, project: create(:project, company: company, owner: owner))
    @other_board = create(:board, project: create(:project, company: company, owner: owner))
    @column = create(:board_column, board: @board)
    @other_column = create(:board_column, board: @other_board)
  end

  def backfill
    BoardTask.where(board: [ @board, @other_board ]).find_each { |task| task.update_column(:number, 1000 + task.id) }
    Board.where(id: [ @board, @other_board ]).update_all(last_task_number: 0)

    migration = AddNumberToBoardTasks.new
    migration.suppress_messages { migration.backfill }
  end

  test "each board is numbered from 1 in creation order and its counter continues from the last" do
    later = create(:board_task, board: @board, board_column: @column, created_at: 1.day.ago)
    earlier = create(:board_task, board: @board, board_column: @column, created_at: 2.days.ago)
    elsewhere = create(:board_task, board: @other_board, board_column: @other_column, created_at: 3.days.ago)

    backfill

    assert_equal [ 1, 2 ], [ earlier.reload.number, later.reload.number ]
    assert_equal 1, elsewhere.reload.number
    assert_equal [ 2, 1 ], [ @board.reload.last_task_number, @other_board.reload.last_task_number ]
    assert_equal 3, create(:board_task, board: @board, board_column: @column).number
  end

  test "a board without tasks keeps a zero counter" do
    backfill

    assert_equal 0, @board.reload.last_task_number
  end
end
