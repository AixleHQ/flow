# frozen_string_literal: true

require "test_helper"

class BoardActivityResourceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company, name: "Ada Lovelace")
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    @task = create(:board_task, board: @board, board_column: @column, title: "Ship it")
  end

  test "workflow events describe the workflow and task, including cancellation" do
    descriptions = %w[workflow_started workflow_completed workflow_failed workflow_cancelled].map do |event_type|
      describe_activity(event_type, metadata: { "workflow_name" => "Nightly build" })
    end

    assert_equal [ "Workflow 'Nightly build' started on 'Ship it'",
                   "Workflow 'Nightly build' completed on 'Ship it'",
                   "Workflow 'Nightly build' failed on 'Ship it'",
                   "Workflow 'Nightly build' cancelled on 'Ship it'" ], descriptions
  end

  test "a deleted comment names who deleted it and on which task" do
    assert_equal "Ada Lovelace deleted a comment on 'Ship it'",
                 describe_activity("comment_deleted", actor_type: :human, metadata: { "preview" => "Typo here" })
  end

  test "unmapped events fall back to a humanized actor sentence" do
    assert_equal "Ada Lovelace performed task archived",
                 describe_activity("task_archived", actor_type: :human)
  end

  test "a nullified actor (permanently-deleted user) renders as Deleted user" do
    activity = BoardActivity.create!(
      board: @board, board_task: @task, event_type: :task_created,
      actor: nil, actor_type: :human
    )
    resource = BoardActivityResource.new(activity).to_h

    assert_equal "Deleted user", resource["actorName"]
    assert_equal "Deleted user created 'Ship it'", resource["description"]
  end

  test "an edit names its changed fields, and the values are left out when asked" do
    activity = BoardActivity.create!(
      board: @board, board_task: @task, event_type: :task_updated, actor: @user, actor_type: :human,
      metadata: { "changes" => { "description" => [ "Old secret", "New secret" ] }, "source" => "api" }
    )

    full = BoardActivityResource.new(activity).to_h
    feed = BoardActivityResource.new(activity, params: { without_changes: true }).to_h

    assert_equal [ "Description" ], feed["changedFields"]
    assert_equal({ "source" => "api" }, feed["metadata"])
    assert_equal [ "Old secret", "New secret" ], full["metadata"]["changes"]["description"]
  end

  private

  def describe_activity(event_type, actor_type: :system, metadata: {})
    activity = BoardActivity.create!(
      board: @board, board_task: @task, event_type:,
      actor: @user, actor_type:, metadata:
    )
    BoardActivityResource.new(activity).to_h["description"]
  end
end
