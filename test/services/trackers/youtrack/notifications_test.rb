# frozen_string_literal: true

require "test_helper"

class Trackers::Youtrack::NotificationsTest < ActiveSupport::TestCase
  PROJECT = { "id" => "0-1", "key" => "APP", "status_field" => "Stage", "assignee_field" => "Owners" }.freeze

  def parse(payload) = Trackers::Youtrack::Notifications.parse(payload, project: PROJECT)

  test "an event is for its subscription's project whatever short name the payload carries" do
    notification = parse(youtrack_event("issue_created", project: "RENAMED", at: 1_790_000_000_000)).sole

    assert_equal [ :issue_created, "0-1", "APP-1", { login: "jdoe" }, Time.zone.at(1_790_000_000).iso8601(3) ],
                 [ notification.kind, notification.scope_id, notification.issue_id, notification.actor, notification.occurred_at ]
    assert_empty Trackers::Youtrack::Notifications.parse(youtrack_event("issue_created"), project: nil)
    assert_empty parse(youtrack_event("issue_created").except("version"))
  end

  test "an update carries the status change and one assignee change per person added" do
    payload = youtrack_event("issue_updated", at: 1_790_000_000_000, changes: {
      "status" => { "from" => "Open", "to" => "Ready for AI" }, "assignee" => { "from" => [ "ann" ], "to" => [ "ann", "aixle" ] }
    })

    notification = parse(payload).sole
    assert_equal [ { field: "status", from: "Open", to: "Ready for AI" }, { field: "assignee", from: "ann", to: "aixle" } ],
                 notification.changes
    assert_equal "1790000000000", notification.revision
    assert_empty parse(youtrack_event("issue_updated", changes: { "assignee" => { "from" => "ann", "to" => nil } }))
  end

  test "each added comment is a notification with its id when the app has one; text never travels" do
    payload = youtrack_event("comment_added", comments: [ { "id" => "4-7", "author" => "jdoe", "created" => 1_790_000_000_000 },
                                                          { "id" => nil, "author" => "ann" } ])

    first, second = parse(payload)
    assert_equal [ "4-7", nil, { login: "jdoe" }, Time.zone.at(1_790_000_000).iso8601(3) ],
                 [ first.comment_id, first.comment_text, first.actor, first.occurred_at ]
    assert_equal [ nil, { login: "ann" } ], [ second.comment_id, second.actor ]
    assert_empty parse(youtrack_event("work_item_added"))
  end
end
