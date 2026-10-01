# frozen_string_literal: true

require "test_helper"

class Trackers::Github::NotificationsTest < ActiveSupport::TestCase
  ROADMAP = FakeGithub::ProjectsApi::ROADMAP
  PROJECTS = [ { "id" => ROADMAP, "status_field" => "Status" }, { "id" => "PVT_other" } ].freeze

  def parse(event, payload) = Trackers::Github::Notifications.parse(event, payload.deep_stringify_keys, projects: PROJECTS)

  def item(action, content_type: "Issue", project: ROADMAP, **extra)
    { action: action, sender: { id: 1, login: "ada" },
      projects_v2_item: { node_id: "PVTI_1", project_node_id: project, content_node_id: "I_kwDOissue1",
                          content_type: content_type, updated_at: "2026-10-01T10:00:00Z" }, **extra }
  end

  test "an item added to a tracked board is a created issue, keyed by the item" do
    notification = parse("projects_v2_item", item("created")).sole

    assert_equal [ :issue_created, ROADMAP, "I_kwDOissue1", "PVTI_1" ],
                 [ notification.kind, notification.scope_id, notification.issue_id, notification.revision ]
    assert_equal({ id: "1", name: "ada" }, notification.actor)
  end

  test "a Status edit is a status change with the option names; other fields and boards are not" do
    changes = { field_value: { field_node_id: "PVTSSF_status", field_type: "single_select", field_name: "Status",
                               from: { id: "opt-todo", name: "Todo" }, to: { id: "opt-ready", name: "Ready for AI" } } }
    notification = parse("projects_v2_item", item("edited", changes: changes)).sole

    assert_equal [ { field: "status", from: "Todo", to: "Ready for AI" } ], notification.changes
    assert_empty parse("projects_v2_item", item("edited", changes: { field_value: { field_type: "single_select", field_name: "Priority" } }))
    assert_empty parse("projects_v2_item", item("created", project: "PVT_untracked"))
    assert_empty parse("projects_v2_item", item("created", content_type: "DraftIssue"))
    assert_empty parse("projects_v2_item", item("reordered"))
  end

  test "an assignment and a comment name only the repository, so every tracked board hears of them" do
    issue = { node_id: "I_kwDOissue1", number: 1, updated_at: "2026-10-01T10:00:00Z" }
    assigned = parse("issues", { action: "assigned", issue: issue, assignee: { login: "aixle-flow[bot]" }, sender: { id: 2, login: "bo" } })
    commented = parse("issue_comment", { action: "created", issue: issue, sender: { login: "bo" },
                                         comment: { node_id: "IC_9", body: "@aixle-flow go", user: { id: 2, login: "bo" }, created_at: "2026-10-01T10:01:00Z" } })

    assert_equal [ ROADMAP, "PVT_other" ], assigned.map(&:scope_id)
    assert_equal [ { field: "assignee", from: nil, to: "aixle-flow[bot]" } ], assigned.first.changes
    assert_equal [ [ :comment_created, "IC_9", "@aixle-flow go" ] ] * 2, commented.map { |n| [ n.kind, n.comment_id, n.comment_text ] }
    assert_empty parse("issues", { action: "unassigned", issue: issue, assignee: { login: "x" } })
  end
end
