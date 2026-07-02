# frozen_string_literal: true

require "test_helper"

class BoardColumnTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @owner = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @owner)
    @board = Board.create!(name: "Board", project: @project)
  end

  # == Validations ==

  test "valid with all required fields" do
    column = BoardColumn.new(name: "Backlog", board: @board)
    assert column.valid?
  end

  test "invalid without name" do
    column = BoardColumn.new(board: @board)
    refute_predicate column, :valid?
    assert column.errors[:name].present?
  end

  test "invalid without board" do
    column = BoardColumn.new(name: "Backlog")
    refute_predicate column, :valid?
  end

  test "position uniqueness scoped to board" do
    BoardColumn.create!(name: "Backlog", board: @board, position: 1)
    duplicate = BoardColumn.new(name: "Todo", board: @board, position: 1)
    refute_predicate duplicate, :valid?
    assert duplicate.errors[:position].present?
  end

  test "same position allowed on different boards" do
    other_project = create(:project, company: @company, owner: @owner)
    other_board = Board.create!(name: "Other", project: other_project)

    BoardColumn.create!(name: "Backlog", board: @board, position: 1)
    column = BoardColumn.new(name: "Backlog", board: other_board, position: 1)
    assert column.valid?
  end

  # == Auto-position ==

  test "auto-assigns position on create" do
    col1 = BoardColumn.create!(name: "Backlog", board: @board)
    col2 = BoardColumn.create!(name: "Done", board: @board)

    assert_equal 1, col1.position
    assert_equal 2, col2.position
  end

  test "auto-assigns next position after existing" do
    BoardColumn.create!(name: "A", board: @board, position: 5)
    col = BoardColumn.create!(name: "B", board: @board)
    assert_equal 6, col.position
  end

  test "does not override explicit position" do
    col = BoardColumn.create!(name: "A", board: @board, position: 10)
    assert_equal 10, col.position
  end

  # == Associations ==

  test "belongs to board" do
    column = BoardColumn.create!(name: "Backlog", board: @board)
    assert_equal @board, column.board
  end

  test "destroying board destroys columns" do
    BoardColumn.create!(name: "Backlog", board: @board)
    BoardColumn.create!(name: "Done", board: @board)

    assert_difference("BoardColumn.count", -2) do
      @board.destroy
    end
  end

  test "board columns ordered by position" do
    col3 = BoardColumn.create!(name: "C", board: @board, position: 3)
    col1 = BoardColumn.create!(name: "A", board: @board, position: 1)
    col2 = BoardColumn.create!(name: "B", board: @board, position: 2)

    assert_equal [ col1, col2, col3 ], @board.board_columns.to_a
  end

  # == Ransack ==

  test "ransackable_attributes returns expected fields" do
    attrs = BoardColumn.ransackable_attributes
    assert_includes attrs, "name"
    assert_includes attrs, "position"
    assert_includes attrs, "purpose"
  end
end
