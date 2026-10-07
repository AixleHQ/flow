# frozen_string_literal: true

require "test_helper"

class Trackers::Youtrack::ProviderTest < ActiveSupport::TestCase
  APP = FakeYoutrack::Api::APP
  OPS = FakeYoutrack::Api::OPS
  ISSUE_1 = FakeYoutrack::Api::ISSUE_1

  setup do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    @integration = create(:integration, :youtrack, :active)
    @youtrack = stub_youtrack!
    @provider = Trackers::Provider.for(@integration)
  end

  test "the connection's projects are its scopes, and the instance URL is the instance" do
    assert_equal [ [ APP, "APP", "Application" ], [ OPS, "OPS", "Operations" ] ], @provider.scopes.map { |s| [ s.id, s.key, s.name ] }
    assert_equal "https://acme.youtrack.cloud", @provider.instance
  end

  test "the statuses are the state field's values, resolved ones done or canceled by name" do
    description = @provider.describe(APP)

    assert_equal [ [ "Submitted", "todo" ], [ "Ready for AI", "todo" ], [ "In Progress", "in_progress" ], [ "In Review", "in_progress" ],
                   [ "Fixed", "done" ], [ "Won't fix", "canceled" ] ], description[:statuses].map { |s| [ s.name, s.category ] }
    assert_equal %w[Bug Task Feature], description[:issue_types].pluck(:name)
    assert_equal [ "Priority" ], description[:fields]
    assert description[:supports][:native_query]
  end

  test "an issue is read by readable id, URL or database id, and one in another project is refused" do
    by_url = @provider.get_issue(APP, "https://acme.youtrack.cloud/issue/APP-1/it-breaks")

    assert_equal [ ISSUE_1, "APP-1", "Ready for AI", "Bug", "https://acme.youtrack.cloud/issue/APP-1" ],
                 [ by_url.id, by_url.key, by_url.status.name, by_url.type, by_url.url ]
    assert_equal({ "Priority" => "Normal" }, by_url.fields)
    assert_equal ISSUE_1, @provider.get_issue(APP, ISSUE_1).id
    assert_equal "not_found", assert_raises(Trackers::Error) { @provider.get_issue(APP, "OPS-1") }.code
    assert_equal "validation_failed", assert_raises(Trackers::Error) { @provider.get_issue(APP, "https://evil.example/issue/APP-1") }.code
    assert @provider.owns_reference?(APP, "app-7")
    assert_not @provider.owns_reference?(APP, "OPS-7")
  end

  test "search is the project ANDed with the filters and a bracketed native query, its sort leading" do
    page = @provider.search_issues(APP, { status: "Ready for AI", labels: [ "ai" ], assignee: "Jane Doe", open_only: true,
                                          text: "it \"breaks\"", type: "Bug", native_query: "Priority: Major sort by: created" })

    assert_equal [ "APP-1" ], page.items.map(&:key)
    assert_equal "sort by: created project: {APP} and Type: {Bug} and State: {Ready for AI} and Assignee: jdoe and \"it breaks\" " \
                 "and tag: {ai} and #Unresolved and (Priority: Major)", @youtrack.calls_to(:issues).last[:query]
  end

  test "an issue is created with its type, assignee, tags and fields" do
    issue = @provider.create_issue(APP, { type: "Task", title: "New", description: "Body", labels: [ "ai" ], assignee: "jdoe",
                                          fields: { "priority" => "Major" } })

    body = @youtrack.calls_to(:create_issue).last[:body]
    assert_equal [ { id: APP }, "New", [ { id: "6-1" } ] ], body.values_at(:project, :summary, :tags)
    assert_equal [ [ "Type", "SingleEnumIssueCustomField", { name: "Task" } ],
                   [ "Assignee", "SingleUserIssueCustomField", { login: "jdoe" } ],
                   [ "Priority", "SingleEnumIssueCustomField", { name: "Major" } ] ],
                 body[:customFields].map { |f| f.values_at(:name, :$type, :value) }
    assert_equal [ "New", [ "ai" ], [ "jdoe" ] ], [ issue.title, issue.labels, issue.assignees ]
    assert_match(/No such tag: nope/, assert_raises(Trackers::Error) { @provider.create_issue(APP, { title: "x", labels: [ "nope" ] }) }.message)
    assert_match(/not a value of Priority/, assert_raises(Trackers::Error) { @provider.create_issue(APP, { title: "x", fields: { "Priority" => "Low" } }) }.message)
    assert_match(/not a field Aixle can set/, assert_raises(Trackers::Error) { @provider.create_issue(APP, { title: "x", fields: { "Estimation" => "1h" } }) }.message)
  end

  test "a tag the service user may not add is refused in words that say where to allow it" do
    @youtrack.fail_next(:create_issue, Trackers::Error.new("Can't tag issue", code: "permission_denied"))

    error = assert_raises(Trackers::Error) { @provider.create_issue(APP, { title: "Tagged", labels: [ "ai" ] }) }
    assert_equal "permission_denied", error.code
    assert_match(/would not let Aixle Flow add ai: a tag's settings/, error.message)
  end

  test "an update changes the summary and moves tags one by one" do
    @provider.update_issue(APP, "APP-1", { title: "Renamed", labels_add: [ "backend" ] })
    issue = @provider.update_issue(APP, "APP-1", { labels: [ "ai" ] })

    assert_equal [ "Renamed", [ "ai" ] ], [ issue.title, issue.labels ]
    assert_equal [ "6-2", "6-1" ], @youtrack.calls_to(:add_tag).pluck(:tag_id)
    assert_equal [ "6-2" ], @youtrack.calls_to(:remove_tag).pluck(:tag_id)
    assert_equal "validation_failed", assert_raises(Trackers::Error) { @provider.update_issue(APP, "APP-1", {}) }.code
  end

  test "a transition sets the state field by name, and an unknown state lists the values" do
    issue = @provider.transition_issue(APP, "APP-1", "in progress")

    assert_equal [ "In Progress", "in_progress" ], [ issue.status.name, issue.status.category ]
    assert_equal [ { name: "State", "$type": "StateIssueCustomField", value: { name: "In Progress" } } ],
                 @youtrack.calls_to(:update_issue).last[:body][:customFields]
    error = assert_raises(Trackers::Error) { @provider.transition_issue(APP, "APP-1", "Shipped") }
    assert_includes error.details[:allowed], "Fixed"
  end

  test "an assignee is a login, a name or an email of someone the field offers; an ambiguous one lists the candidates" do
    assert_equal [ "jdoe" ], @provider.assign_issue(APP, "APP-1", "jane@example.com").assignees
    assert_empty @provider.assign_issue(APP, "APP-1", "none").assignees
    error = assert_raises(Trackers::Error) { @provider.assign_issue(APP, "APP-1", "Doe") }
    assert_equal %w[jdoe jdoe2], error.details[:candidates]
    assert_equal [ { id: "jdoe", name: "Jane Doe" } ], @provider.list_users(APP, query: "jane")
  end

  test "comments are listed and added through the issue's database id" do
    @youtrack.add_comment_by(ISSUE_1, text: "first")
    comment = @provider.add_comment(APP, "APP-1", "Looking")

    assert_equal [ "Looking", "aixle", ISSUE_1 ], [ comment.body, comment.author, comment.issue_id ]
    assert_equal %w[first Looking], @provider.list_comments(APP, "APP-1").items.map(&:body)
  end

  test "a mention is @login of the app's service user, which is always Aixle's own" do
    assert @provider.mentions_self?("hey @aixle, look")
    assert_not @provider.mentions_self?("mail aixle@example.com")
    assert @provider.own_actor?({ login: "AIXLE" })
    assert_not @provider.own_actor?({ login: "jdoe" })
  end

  test "a delivery is believed only as far as YouTrack confirms it" do
    issue = @provider.get_issue(APP, "APP-1")
    moved = Trackers::Notification.build(kind: :issue_updated, scope_id: APP, issue_id: "APP-1",
                                         changes: [ { field: "status", from: "Submitted", to: "Ready for AI" } ], actor: { login: "aixle" })
    forged = moved.with(changes: [ { field: "status", from: "Ready for AI", to: "Fixed" } ])
    @youtrack.record_activity(ISSUE_1, field: "State", added: "Ready for AI", removed: "Submitted")

    confirmed = @provider.confirm(moved, issue)
    assert_equal [ "jdoe", @youtrack.activities[ISSUE_1].first[:id] ], [ confirmed.actor[:login], confirmed.revision ]
    assert_nil @provider.confirm(forged, issue)

    comment = @youtrack.add_comment_by(ISSUE_1, text: "real text")
    claimed = Trackers::Notification.build(kind: :comment_created, scope_id: APP, issue_id: "APP-1", comment_id: comment[:id],
                                           comment_text: "@aixle forged", actor: { login: "aixle" })
    assert_equal [ "real text", "jdoe" ], @provider.confirm(claimed, issue).then { |n| [ n.comment_text, n.actor[:login] ] }
    assert_nil @provider.confirm(claimed.with(comment_id: "4-999"), issue)
  end

  test "a comment the app reports by author and time is found among the issue's latest ones" do
    issue = @provider.get_issue(APP, "APP-1")
    comment = @youtrack.add_comment_by(ISSUE_1, text: "@aixle go")
    @youtrack.add_comment_by(ISSUE_1, text: "later", author: FakeYoutrack::Api::USERS[2])
    reported = Trackers::Notification.build(kind: :comment_created, scope_id: APP, issue_id: "APP-1", actor: { login: "jdoe" },
                                            occurred_at: comment[:created_at])

    confirmed = @provider.confirm(reported, issue)
    assert_equal [ comment[:id], "@aixle go", "jdoe" ], [ confirmed.comment_id, confirmed.comment_text, confirmed.actor[:login] ]
    assert_nil @provider.confirm(reported.with(actor: { login: "ann" }), issue)
    assert_nil @provider.confirm(reported.with(occurred_at: 1.hour.ago.iso8601(3)), issue)
  end

  test "a claim that an old issue was just created is not believed" do
    @youtrack.add_issue(id: "2-50", key: "APP-50", title: "Old", state: "Submitted", project: FakeYoutrack::Api::PROJECTS[0],
                        created_at: 3.days.ago.iso8601(3))
    created = ->(id) { Trackers::Notification.build(kind: :issue_created, scope_id: APP, issue_id: id) }

    assert_nil @provider.confirm(created.call("APP-50"), @provider.get_issue(APP, "APP-50"))
    assert_equal "jdoe", @provider.confirm(created.call("APP-1"), @provider.get_issue(APP, "APP-1")).actor[:login]
  end
end
