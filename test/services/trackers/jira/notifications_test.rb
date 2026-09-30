# frozen_string_literal: true

require "test_helper"

class Trackers::Jira::NotificationsTest < ActiveSupport::TestCase
  PROJECTS = [ { "id" => "10000", "key" => "ENG" } ].freeze

  def payload(event, **extra)
    { "timestamp" => 1_727_690_400_000, "webhookEvent" => event,
      "user" => { "accountId" => "557058:ada", "displayName" => "Ada Lovelace" },
      "issue" => { "id" => "10100", "key" => "ENG-1", "fields" => { "project" => { "id" => "10000", "key" => "ENG" } } } }
      .merge(extra.transform_keys(&:to_s))
  end

  def parse(body) = Trackers::Jira::Notifications.parse(body, projects: PROJECTS)

  test "a status and an assignee change come through with Jira's ids beside the names" do
    body = payload("jira:issue_updated", changelog: { "id" => "30001", "items" => [
      { "field" => "status", "fieldId" => "status", "from" => "10004", "fromString" => "Ready for AI", "to" => "3", "toString" => "In Progress" },
      { "field" => "assignee", "fieldId" => "assignee", "from" => nil, "fromString" => nil, "to" => "557058:ada", "toString" => "Ada Lovelace" },
      { "field" => "description", "fieldId" => "description", "fromString" => "a", "toString" => "b" }
    ] })

    notification = parse(body).sole

    assert_equal [ :issue_updated, "10000", "10100", "30001" ],
                 [ notification.kind, notification.scope_id, notification.issue_id, notification.revision ]
    assert_equal [ { field: "status", from: "Ready for AI", to: "In Progress", from_id: "10004", to_id: "3" },
                   { field: "assignee", to: "Ada Lovelace", to_id: "557058:ada" } ], notification.changes
    assert_equal({ id: "557058:ada", name: "Ada Lovelace" }, notification.actor)
    assert_equal Time.utc(2024, 9, 30, 10), Time.zone.parse(notification.occurred_at)
  end

  test "an edit that changed neither status nor assignee is nothing to report" do
    assert_empty parse(payload("jira:issue_updated", changelog: { "id" => "1", "items" => [ { "field" => "summary" } ] }))
    assert_empty parse(payload("jira:issue_updated"))
  end

  test "a new issue and a new comment" do
    created = parse(payload("jira:issue_created")).sole
    comment = parse(payload("comment_created", comment: { "id" => "77", "body" => "[~accountid:bot] please",
                                                          "author" => { "accountId" => "557058:alan", "displayName" => "Alan" } })).sole

    assert_equal [ :issue_created, "created" ], [ created.kind, created.revision ]
    assert_equal [ :comment_created, "77", "[~accountid:bot] please", { id: "557058:alan", name: "Alan" } ],
                 [ comment.kind, comment.comment_id, comment.comment_text, comment.actor ]
  end

  test "an issue whose event carries no project is placed by its key; one in another project is dropped" do
    keyed = payload("jira:issue_created")
    keyed["issue"]["fields"] = {}
    other = payload("jira:issue_created")
    other["issue"]["fields"]["project"] = { "id" => "10001" }

    assert_equal "10000", parse(keyed).sole.scope_id
    assert_empty parse(other)
    assert_empty parse(payload("jira:issue_deleted"))
  end
end
