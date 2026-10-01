# frozen_string_literal: true

require "test_helper"

class Trackers::Linear::ProviderTest < ActiveSupport::TestCase
  ENG = FakeLinear::Api::ENG
  OPS = FakeLinear::Api::OPS

  setup do
    @integration = create(:integration, :linear, :active)
    @linear = stub_linear!
    @provider = Trackers::Provider.for(@integration)
  end

  test "the connection's teams are its scopes, and the workspace is the instance" do
    assert_equal [ [ ENG, "ENG", "Engineering" ], [ OPS, "OPS", "Operations" ] ], @provider.scopes.map { |s| [ s.id, s.key, s.name ] }
    assert_equal FakeLinear::Api::ORGANIZATION, @provider.instance
  end

  test "the statuses are the team's workflow states, categorized by their type" do
    description = @provider.describe(ENG)

    assert_equal [ [ "Backlog", "todo" ], [ "Ready for AI", "todo" ], [ "In Progress", "in_progress" ], [ "Done", "done" ],
                   [ "Canceled", "canceled" ] ], description[:statuses].map { |s| [ s.name, s.category ] }
    assert_equal [ "Issue" ], description[:issue_types].pluck(:name)
    assert_not description[:supports][:native_query]
  end

  test "an issue is read by identifier, URL or id, and one in another team is refused" do
    by_url = @provider.get_issue(ENG, "https://linear.app/acme/issue/ENG-1/it-breaks")

    assert_equal [ FakeLinear::Api::ISSUE_1, "ENG-1", "Ready for AI", "todo" ], [ by_url.id, by_url.key, by_url.status.name, by_url.status.category ]
    assert_equal by_url.id, @provider.get_issue(ENG, FakeLinear::Api::ISSUE_1).id
    assert_equal "not_found", assert_raises(Trackers::Error) { @provider.get_issue(ENG, "OPS-1") }.code
    assert_equal "validation_failed", assert_raises(Trackers::Error) { @provider.get_issue(ENG, "https://linear.app/evil/issue/ENG-1") }.code
  end

  test "search is scoped to the team with structured filters and has no native query" do
    page = @provider.search_issues(ENG, { status: "Ready for AI", labels: [ "ai" ], assignee: "ada", open_only: true, text: "breaks" })

    assert_equal [ "ENG-1" ], page.items.map(&:key)
    assert_equal({ and: [
      { team: { id: { eq: ENG } } }, { state: { name: { eqIgnoreCase: "Ready for AI" } } },
      { state: { type: { nin: %w[completed canceled duplicate] } } },
      { assignee: { id: { eq: FakeLinear::Api::MEMBERS[0][:id] } } }, { title: { containsIgnoreCase: "breaks" } },
      { labels: { some: { name: { eqIgnoreCase: "ai" } } } }
    ] }, @linear.calls_to(:issues).last[:filter])
    assert_equal "validation_failed", assert_raises(Trackers::Error) { @provider.search_issues(ENG, { native_query: "x" }) }.code
    assert_equal "validation_failed", assert_raises(Trackers::Error) { @provider.search_issues(ENG, { type: "Bug" }) }.code
  end

  test "an issue is created in the team with labels and an assignee looked up by name" do
    issue = @provider.create_issue(ENG, { type: "Issue", title: "New", description: "Body", labels: [ "Bug" ], assignee: "Ada Lovelace",
                                          fields: { "priority" => 2 } })

    assert_equal({ teamId: ENG, title: "New", description: "Body", assigneeId: FakeLinear::Api::MEMBERS[0][:id], labelIds: [ "lb-bug" ],
                   priority: 2 }, @linear.calls_to(:create_issue).last[:input])
    assert_equal [ "New", [ "Bug" ], [ "ada" ] ], [ issue.title, issue.labels, issue.assignees ]
    assert_equal "validation_failed", assert_raises(Trackers::Error) { @provider.create_issue(ENG, { title: "x", type: "Epic" }) }.code
    assert_match(/No such label: nope/, assert_raises(Trackers::Error) { @provider.create_issue(ENG, { title: "x", labels: [ "nope" ] }) }.message)
  end

  test "an ambiguous assignee is refused with the candidates" do
    error = assert_raises(Trackers::Error) { @provider.assign_issue(ENG, "ENG-1", "ad") }

    assert_equal [ "ada", "byron" ], error.details[:candidates]
    assert_equal [ "aixle" ], @provider.assign_issue(ENG, "ENG-1", "@aixle").assignees
    assert_empty @provider.assign_issue(ENG, "ENG-1", "none").assignees
  end

  test "transition sets a state of the team by name, and lists the states otherwise" do
    assert_equal "In Progress", @provider.transition_issue(ENG, "ENG-1", "in progress").status.name
    assert_equal({ stateId: "st-progress" }, @linear.calls_to(:update_issue).last[:input])

    error = assert_raises(Trackers::Error) { @provider.transition_issue(ENG, "ENG-1", "Shipped") }
    assert_includes error.details[:allowed], "Ready for AI"
  end

  test "update adds and removes labels by name" do
    issue = @provider.update_issue(ENG, "ENG-1", { title: "Renamed", labels_add: [ "ai" ] })
    assert_equal [ "Renamed", [ "ai" ] ], [ issue.title, issue.labels ]

    assert_empty @provider.update_issue(ENG, "ENG-1", { labels_remove: [ "ai" ] }).labels
    assert_equal "validation_failed", assert_raises(Trackers::Error) { @provider.update_issue(ENG, "ENG-1", {}) }.code
  end

  test "users are the team's members, and comments are read and written on the issue" do
    assert_equal [ "ada", "byron" ], @provider.list_users(ENG, query: "ada").pluck(:name)

    comment = @provider.add_comment(ENG, "ENG-1", "On it")
    assert_equal [ FakeLinear::Api::ISSUE_1, "On it" ], [ comment.issue_id, comment.body ]
    assert_equal [ comment.id ], @provider.list_comments(ENG, "ENG-1").items.map(&:id)
  end

  test "a status change names the state it left, read from the team's states" do
    issue = @provider.get_issue(ENG, "ENG-1")

    assert_equal({ "field" => "status", "from" => { "name" => "Backlog", "category" => "todo" },
                   "to" => { "name" => "Ready for AI", "category" => "todo" } },
                 @provider.status_change([ { field: "status", from_id: "st-backlog", to_id: "st-ready", to: "Ready for AI" } ], issue))
  end

  test "a kept-for-Aixle account is the identity; mentions match its username or profile link" do
    assert @provider.own_actor?({ id: FakeLinear::Api::BOT_ID, name: "someone" })
    assert @provider.mentions_self?("hey @aixle please")
    assert @provider.mentions_self?("[Aixle](https://linear.app/acme/profiles/aixle) take it")
    assert_not @provider.mentions_self?("@aixle-docs")

    @integration.update!(settings: @integration.settings.merge("dedicated_identity" => false))
    assert_nil Trackers::Provider.for(@integration).identity
  end

  test "a reference belongs to the team its key starts with" do
    assert @provider.owns_reference?(ENG, "eng-12")
    assert_not @provider.owns_reference?(ENG, "OPS-1")
    assert_equal "ENG-12", @provider.issue_identifier("https://linear.app/acme/issue/ENG-12/slug")
  end
end
