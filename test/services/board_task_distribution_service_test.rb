# frozen_string_literal: true

require "test_helper"

class BoardTaskDistributionServiceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :employee, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, project: @project)
    @backlog = create(:board_column, board: @board, name: "Backlog", position: 1)
    @done = create(:board_column, board: @board, name: "Done", position: 2)

    create(:board_task, board: @board, board_column: @backlog)
    create(:board_task, board: @board, board_column: @backlog, archived_at: Time.current)
    create(:board_task, board: @board, board_column: @done, archived_at: Time.current)
  end

  test "excludes archived tasks by default" do
    result = BoardTaskDistributionService.new(@company, project: @project).call

    assert_equal [ { name: "Backlog", count: 1 }, { name: "Done", count: 0 } ], result.to_h[:columns]
    assert_equal 1, result.total
  end

  test "includes archived tasks when requested" do
    result = BoardTaskDistributionService.new(@company, project: @project, include_archived: true).call

    assert_equal [ { name: "Backlog", count: 2 }, { name: "Done", count: 1 } ], result.to_h[:columns]
    assert_equal 3, result.total
  end
end
