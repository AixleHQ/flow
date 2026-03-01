# frozen_string_literal: true

require "test_helper"

class ActivityRecorderTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    @task = create(:board_task, board: @board, board_column: @column)
  end

  test "records activity and returns it" do
    activity = ActivityRecorder.record(
      board: @board, event_type: :task_created, actor: @user,
      actor_type: :human, task: @task, metadata: { title: "Test" }
    )
    assert activity.is_a?(BoardActivity)
    assert activity.persisted?
    assert_equal "task_created", activity.event_type
  end

  test "records activity without task" do
    activity = ActivityRecorder.record(
      board: @board, event_type: :task_deleted, actor: @user,
      actor_type: :human, metadata: { title: "Deleted" }
    )
    assert activity.persisted?
    assert_nil activity.board_task_id
  end

  test "non-blocking on error" do
    result = ActivityRecorder.record(
      board: @board, event_type: :task_created, actor: nil,
      actor_type: :human
    )
    assert_nil result
  end
end
