# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261125120000_strip_changes_from_task_updated_activities")

class StripChangesFromTaskUpdatedActivitiesTest < ActiveSupport::TestCase
  test "removes the changes key from task_updated rows and keeps other metadata" do
    board = create(:board)
    activity = BoardActivity.create!(board: board, event_type: :task_updated, actor_type: :system,
                                     metadata: { "changes" => { "title" => %w[Old New] }, "note" => "kept" })
    other = BoardActivity.create!(board: board, event_type: :task_created, actor_type: :system,
                                  metadata: { "changes" => "kept" })

    migration = StripChangesFromTaskUpdatedActivities.new
    migration.suppress_messages { migration.up }

    assert_equal({ "note" => "kept" }, activity.reload.metadata)
    assert_equal({ "changes" => "kept" }, other.reload.metadata)
  end
end
