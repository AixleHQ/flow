# frozen_string_literal: true

require "test_helper"

class BoardViewPresetTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @user2 = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, project: @project)
  end

  test "valid preset" do
    preset = BoardViewPreset.new(board: @board, user: @user, name: "My Work", filters: { assignee_id_eq: @user.id })
    assert preset.valid?
  end

  test "requires name" do
    preset = BoardViewPreset.new(board: @board, user: @user, filters: { assignee_id_eq: 1 })
    assert_not preset.valid?
    assert_includes preset.errors[:name], "can't be blank"
  end

  test "requires filters" do
    preset = BoardViewPreset.new(board: @board, user: @user, name: "Test")
    assert_not preset.valid?
    assert_includes preset.errors[:filters], "can't be blank"
  end

  test "name unique per board + user" do
    BoardViewPreset.create!(board: @board, user: @user, name: "Bugs", filters: { task_type_eq: "bug" })
    dupe = BoardViewPreset.new(board: @board, user: @user, name: "Bugs", filters: { priority_eq: "high" })
    assert_not dupe.valid?
  end

  test "same name allowed for different users" do
    BoardViewPreset.create!(board: @board, user: @user, name: "Bugs", filters: { task_type_eq: "bug" })
    other = BoardViewPreset.new(board: @board, user: @user2, name: "Bugs", filters: { task_type_eq: "bug" })
    assert other.valid?
  end

  test "visible_to includes personal and shared" do
    personal = BoardViewPreset.create!(board: @board, user: @user, name: "Mine", filters: { a: 1 })
    shared = BoardViewPreset.create!(board: @board, user: @user2, name: "Shared", filters: { b: 2 }, shared: true)
    other_private = BoardViewPreset.create!(board: @board, user: @user2, name: "Private", filters: { c: 3 })

    visible = BoardViewPreset.visible_to(@user)
    assert_includes visible, personal
    assert_includes visible, shared
    assert_not_includes visible, other_private
  end
end
