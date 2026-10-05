# frozen_string_literal: true

require "test_helper"

class Trackers::Youtrack::NotificationsTest < ActiveSupport::TestCase
  PROJECT = { "id" => "0-1", "key" => "APP", "status_field" => "Stage", "assignee_field" => "Owners" }.freeze

  def parse(payload) = Trackers::Youtrack::Notifications.parse(payload, project: PROJECT)

  test "a delivery is for its subscription's project whatever short name the payload carries" do
    notification = parse(youtrack_payload("issueCreated", project: "RENAMED", reporter: { "login" => "jdoe", "fullName" => "Jane Doe" })).sole

    assert_equal [ :issue_created, "0-1", "APP-1", { login: "jdoe", name: "Jane Doe" } ],
                 [ notification.kind, notification.scope_id, notification.issue_id, notification.actor ]
    assert_empty Trackers::Youtrack::Notifications.parse(youtrack_payload("issueCreated"), project: nil)
  end

  test "an update keeps the project's status and assignee fields, one change per person added" do
    payload = youtrack_payload("issueUpdated", updated: 1_790_000_000_000, updatedBy: { "login" => "jdoe" }, changedFields: [
      { "name" => "Stage", "oldValue" => { "name" => "Open", "presentation" => "Open" }, "value" => { "name" => "Ready for AI" } },
      { "name" => "Owners", "oldValue" => [ { "login" => "ann" } ], "value" => [ { "login" => "ann" }, { "login" => "aixle" } ] },
      { "name" => "summary", "oldValue" => "a", "value" => "b" }
    ])

    notification = parse(payload).sole
    assert_equal [ { field: "status", from: "Open", to: "Ready for AI" }, { field: "assignee", from: "ann", to: "aixle" } ],
                 notification.changes
    assert_equal "1790000000000", notification.revision
    assert_empty parse(youtrack_payload("issueUpdated", changedFields: [ { "name" => "summary", "value" => "b" } ]))
  end

  test "each added comment is a notification without its text, and events Aixle does not use yield nothing" do
    payload = youtrack_payload("commentAdded", comments: [
      { "id" => "4-1", "text" => "@aixle go", "author" => { "login" => "jdoe" } }, { "id" => "4-2", "text" => "and" }
    ])

    assert_equal [ [ "4-1", nil ], [ "4-2", nil ] ], parse(payload).map { |n| [ n.comment_id, n.comment_text ] }
    assert_empty parse(youtrack_payload("workItemAdded"))
  end
end
