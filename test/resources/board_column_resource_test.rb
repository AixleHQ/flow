# frozen_string_literal: true

require "test_helper"

class BoardColumnResourceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board, name: "Backlog")
  end

  test "tasks_count comes from the with_tasks_count select when the caller loaded it" do
    create_list(:board_task, 2, board: @board, board_column: @column)
    create(:board_task, board: @board, board_column: @column, archived_at: Time.current)

    selected = @board.board_columns.with_tasks_count.find { |c| c.id == @column.id }

    assert_equal 2, BoardColumnResource.new(selected).to_h["tasksCount"]
  end

  test "a column loaded without the count still reports one, by counting its active tasks" do
    create(:board_task, board: @board, board_column: @column)
    create(:board_task, board: @board, board_column: @column, archived_at: Time.current)

    assert_equal 1, BoardColumnResource.new(@column).to_h["tasksCount"]
  end
end
