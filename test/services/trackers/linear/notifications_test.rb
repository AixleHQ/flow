# frozen_string_literal: true

require "test_helper"

class Trackers::Linear::NotificationsTest < ActiveSupport::TestCase
  TEAMS = [ { "id" => "team-eng", "key" => "ENG" } ].freeze

  def parse(payload) = Trackers::Linear::Notifications.parse(payload.deep_stringify_keys, teams: TEAMS)

  def payload(type, action, data, **extra)
    { type: type, action: action, data: data, actor: { id: "u-ada", name: "Ada", type: "user" },
      createdAt: "2026-10-01T10:00:00.000Z", organizationId: "org-1", webhookTimestamp: 1, **extra }
  end

  test "a created issue in a covered team is a notification; another team's is nothing" do
    notification = parse(payload("Issue", "create", { id: "i1", teamId: "team-eng" })).sole

    assert_equal [ :issue_created, "team-eng", "i1", { id: "u-ada", name: "Ada" } ],
                 [ notification.kind, notification.scope_id, notification.issue_id, notification.actor ]
    assert_empty parse(payload("Issue", "create", { id: "i2", teamId: "team-ops" }))
  end

  test "an update names the state and assignee it changed by updatedFrom" do
    data = { id: "i1", teamId: "team-eng", stateId: "st-ready", state: { id: "st-ready", name: "Ready for AI" },
             assigneeId: "u-bot", assignee: { id: "u-bot", name: "Aixle Bot" }, updatedAt: "2026-10-01T10:00:01.000Z" }
    notification = parse(payload("Issue", "update", data, updatedFrom: { stateId: "st-backlog", assigneeId: nil, updatedAt: "x" })).sole

    assert_equal [ { field: "status", from_id: "st-backlog", to_id: "st-ready", to: "Ready for AI" },
                   { field: "assignee", to_id: "u-bot", to: "Aixle Bot" } ], notification.changes
    assert_equal "2026-10-01T10:00:01.000Z", notification.revision
    assert_empty parse(payload("Issue", "update", data, updatedFrom: { title: "Old" }))
  end

  test "a comment names its issue's team" do
    data = { id: "c1", body: "@aixle go", issueId: "i1", issue: { id: "i1", teamId: "team-eng" }, createdAt: "2026-10-01T10:00:00.000Z" }
    notification = parse(payload("Comment", "create", data)).sole

    assert_equal [ :comment_created, "i1", "c1", "@aixle go" ],
                 [ notification.kind, notification.issue_id, notification.comment_id, notification.comment_text ]
    assert_empty parse(payload("Comment", "create", data.merge(issue: { id: "i1", teamId: "team-ops" })))
    assert_empty parse(payload("Comment", "remove", data))
  end
end
