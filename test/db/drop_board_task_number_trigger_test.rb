# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261005092510_drop_board_task_number_trigger")

# schema.rb cannot carry the trigger, so the test puts it back with `down` and
# then takes it away again.
class DropBoardTaskNumberTriggerTest < ActiveSupport::TestCase
  setup do
    company = create(:company)
    owner = create(:user, company: company)
    @board = create(:board, project: create(:project, company: company, owner: owner))
    @column = create(:board_column, board: @board)
    @migration = DropBoardTaskNumberTrigger.new
  end

  test "an insert without a number is numbered while the trigger exists and rejected once it is gone" do
    @migration.suppress_messages { @migration.down }

    inserted = BoardTask.insert_all(
      [ { board_id: @board.id, board_column_id: @column.id, title: "Through the trigger", position: 1 } ],
      returning: %w[number]
    )
    assert_equal [ 1 ], inserted.rows.flatten

    @migration.suppress_messages { @migration.up }

    # A failed statement aborts the test transaction; the savepoint keeps the rest of it usable.
    assert_raises(ActiveRecord::NotNullViolation) do
      BoardTask.transaction(requires_new: true) do
        BoardTask.insert_all(
          [ { board_id: @board.id, board_column_id: @column.id, title: "No number", position: 2 } ]
        )
      end
    end

    assert_equal 2, create(:board_task, board: @board, board_column: @column).number
  end
end
