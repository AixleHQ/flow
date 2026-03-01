# frozen_string_literal: true

require "test_helper"

class BoardActivityTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    @task = create(:board_task, board: @board, board_column: @column)
  end

  test "valid activity" do
    activity = BoardActivity.new(
      board: @board, board_task: @task, event_type: :task_created,
      actor: @user, actor_type: :human, metadata: { title: "Test" }
    )
    assert activity.valid?
  end

  test "requires event_type" do
    activity = BoardActivity.new(board: @board, actor: @user, actor_type: :human)
    assert_not activity.valid?
    assert_includes activity.errors[:event_type], "can't be blank"
  end

  test "requires actor_type" do
    activity = BoardActivity.new(board: @board, event_type: :task_created, actor: @user)
    assert_not activity.valid?
    assert_includes activity.errors[:actor_type], "can't be blank"
  end

  test "board_task is optional" do
    activity = BoardActivity.new(
      board: @board, event_type: :task_deleted, actor: @user, actor_type: :human
    )
    assert activity.valid?
  end

  test "scope for_board" do
    BoardActivity.create!(board: @board, event_type: :task_created, actor: @user, actor_type: :human)
    assert_equal 1, BoardActivity.for_board(@board).count
  end

  test "scope for_task" do
    BoardActivity.create!(board: @board, board_task: @task, event_type: :task_created, actor: @user, actor_type: :human)
    BoardActivity.create!(board: @board, event_type: :task_deleted, actor: @user, actor_type: :human)
    assert_equal 1, BoardActivity.for_task(@task).count
  end

  test "scope by_event_type" do
    BoardActivity.create!(board: @board, event_type: :task_created, actor: @user, actor_type: :human)
    BoardActivity.create!(board: @board, event_type: :task_moved, actor: @user, actor_type: :human)
    assert_equal 1, BoardActivity.by_event_type(:task_created).count
  end

  test "scope since" do
    old = BoardActivity.create!(board: @board, event_type: :task_created, actor: @user, actor_type: :human)
    old.update_column(:created_at, 2.days.ago)
    BoardActivity.create!(board: @board, event_type: :task_moved, actor: @user, actor_type: :human)
    assert_equal 1, BoardActivity.since(1.day.ago).count
  end

  test "no updated_at" do
    activity = BoardActivity.create!(
      board: @board, event_type: :task_created, actor: @user, actor_type: :human
    )
    assert_not activity.has_attribute?(:updated_at)
  end

  test "metadata stores hash" do
    activity = BoardActivity.create!(
      board: @board, event_type: :task_moved, actor: @user, actor_type: :human,
      metadata: { from_column: "Backlog", to_column: "Done" }
    )
    assert_equal "Backlog", activity.reload.metadata["from_column"]
  end
end
