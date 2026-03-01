# frozen_string_literal: true

require "test_helper"

class BoardTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @owner = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @owner)
  end

  # == Validations ==

  test "valid with all required fields" do
    board = Board.new(name: "Sprint Board", project: @project)
    assert board.valid?
  end

  test "invalid without name" do
    board = Board.new(project: @project)
    refute board.valid?
    assert board.errors[:name].present?
  end

  test "invalid without project" do
    board = Board.new(name: "Board")
    refute board.valid?
    assert board.errors[:project].present?
  end

  test "enforces one board per project" do
    Board.create!(name: "First", project: @project)
    duplicate = Board.new(name: "Second", project: @project)
    refute duplicate.valid?
    assert duplicate.errors[:project_id].present?
  end

  test "different projects can each have a board" do
    other_project = create(:project, company: @company, owner: @owner)
    Board.create!(name: "Board A", project: @project)
    board_b = Board.new(name: "Board B", project: other_project)
    assert board_b.valid?
  end

  # == Associations ==

  test "belongs to project" do
    board = Board.create!(name: "Board", project: @project)
    assert_equal @project, board.project
  end

  test "destroying project destroys board" do
    Board.create!(name: "Board", project: @project)
    assert_difference("Board.count", -1) do
      @project.destroy
    end
  end

  test "has_many board_columns ordered by position" do
    board = Board.create!(name: "Board", project: @project)
    assert_equal [], board.board_columns.to_a
    assert board.respond_to?(:board_columns)
  end

  # == create_from_preset ==

  test "create_from_preset creates board with columns" do
    board = Board.create_from_preset(project: @project, preset_key: :dev_team)

    assert board.persisted?
    assert_equal "Dev Team", board.name
    assert_equal "dev_team", board.preset_origin
    assert_equal 5, board.board_columns.count
    assert_equal "Backlog", board.board_columns.first.name
  end

  test "create_from_preset with custom name" do
    board = Board.create_from_preset(project: @project, preset_key: :simple_kanban, name: "My Board")

    assert_equal "My Board", board.name
    assert_equal "simple_kanban", board.preset_origin
    assert_equal 3, board.board_columns.count
  end

  test "create_from_preset raises for invalid preset" do
    assert_raises(ActiveRecord::RecordNotFound) do
      Board.create_from_preset(project: @project, preset_key: :nonexistent)
    end
  end

  test "create_from_preset columns have correct positions and purposes" do
    board = Board.create_from_preset(project: @project, preset_key: :simple_kanban)
    columns = board.board_columns.order(:position)

    assert_equal [ 1, 2, 3 ], columns.map(&:position)
    assert columns.all? { |c| c.purpose.present? }
  end

  # == Ransack ==

  test "ransackable_attributes returns expected fields" do
    attrs = Board.ransackable_attributes
    assert_includes attrs, "name"
    assert_includes attrs, "preset_origin"
  end

  test "ransackable_associations returns expected associations" do
    assocs = Board.ransackable_associations
    assert_includes assocs, "project"
    assert_includes assocs, "board_columns"
  end
end
