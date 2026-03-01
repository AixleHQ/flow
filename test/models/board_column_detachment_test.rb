# frozen_string_literal: true

require "test_helper"

class BoardColumnDetachmentTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @owner = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @owner)
    @board = Board.create_from_preset(project: @project, preset_key: :simple_kanban)
  end

  test "board starts with preset_origin set" do
    assert_equal "simple_kanban", @board.preset_origin
  end

  test "creating a column detaches preset" do
    @board.board_columns.create!(name: "New Column")
    @board.reload
    assert_nil @board.preset_origin
  end

  test "updating a column detaches preset" do
    column = @board.board_columns.first
    column.update!(name: "Renamed")
    @board.reload
    assert_nil @board.preset_origin
  end

  test "destroying a column detaches preset" do
    column = @board.board_columns.first
    column.destroy!
    @board.reload
    assert_nil @board.preset_origin
  end

  test "modifying column on board without preset is safe" do
    @board.update_column(:preset_origin, nil)
    column = @board.board_columns.first

    column.update!(name: "Renamed")
    @board.reload
    assert_nil @board.preset_origin
  end

  test "detachment is one-way" do
    @board.board_columns.create!(name: "Trigger")
    @board.reload
    assert_nil @board.preset_origin

    @board.board_columns.last.destroy!
    @board.reload
    assert_nil @board.preset_origin
  end

  test "preset_origin persists on fresh read after create_from_preset" do
    board = Board.create_from_preset(
      project: create(:project, company: @company, owner: @owner),
      preset_key: :dev_team
    )
    fresh = Board.find(board.id)
    assert_equal "dev_team", fresh.preset_origin
  end
end
