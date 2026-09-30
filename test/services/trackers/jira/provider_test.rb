# frozen_string_literal: true

require "test_helper"

class Trackers::Jira::ProviderTest < ActiveSupport::TestCase
  setup do
    @integration = create(:integration, :jira, :active)
    @jira = stub_jira!
    @provider = Trackers::Provider.for(@integration)
  end

  test "the connection's Jira projects are its scopes, keyed by the project id" do
    assert_equal [ [ "10000", "ENG", "Engineering" ], [ "10001", "OPS", "Operations" ] ],
                 @provider.scopes.map { |s| [ s.id, s.key, s.name ] }
    assert @provider.covers_scope?("10000")
    assert_not @provider.covers_scope?("10002")
    assert_equal "cloud-acme", @provider.instance
  end

  test "the statuses are the board's columns, categorized by the statuses they hold" do
    description = @provider.describe("10000")

    assert_equal [ [ "Backlog", "todo" ], [ "Ready for AI", "todo" ], [ "Doing", "in_progress" ], [ "Done", "done" ] ],
                 description[:statuses].map { |s| [ s.name, s.category ] }
    assert_includes description[:states].map(&:name), "In Review"
    assert_equal %w[Task Bug], description[:issue_types].pluck(:name)
    assert description[:supports][:native_query]
  end

  test "a project without a board has its workflow statuses" do
    assert_equal [ "To Do", "Ready for AI", "In Progress", "In Review", "Done" ], @provider.describe("10001")[:statuses].map(&:name)
  end

  test "an issue's status is its column; the workflow status is kept as the state" do
    issue = @provider.get_issue("10000", "https://acme.atlassian.net/browse/ENG-1")

    assert_equal [ "10100", "ENG-1", "https://acme.atlassian.net/browse/ENG-1" ], [ issue.id, issue.key, issue.url ]
    assert_equal [ "Ready for AI", "todo" ], [ issue.status.name, issue.status.category ]
    assert_equal({ "state" => "Ready for AI", "board_column" => "Ready for AI", "priority" => "Medium" }, issue.fields)
  end

  test "an issue in another Jira project is refused, whatever its id" do
    error = assert_raises(Trackers::Error) { @provider.get_issue("10000", "OPS-1") }

    assert_equal "not_found", error.code
    assert_equal "validation_failed", assert_raises(Trackers::Error) { @provider.get_issue("10000", "https://evil.example.com/browse/ENG-1") }.code
  end

  test "search builds JQL inside the project, and a native query cannot widen it" do
    @jira.add_issue(id: "10300", key: "OPS-7", summary: "Not ours", status_id: "1", project: FakeJira::Api::PROJECTS[1])
    @jira.stubs(:search).returns(issues: @jira.issues.values, next_cursor: "n2")

    page = @provider.search_issues("10000", { status: "Doing", labels: [ "ai" ], open_only: true,
                                              native_query: 'text ~ "x") OR (project = 10001 ORDER BY created ASC' })

    assert_equal [ "ENG-1" ], page.items.map(&:key)
    assert_equal "n2", page.next_cursor
  end

  test "the JQL filters an issue's column by the statuses it holds and quotes every value" do
    @provider.search_issues("10000", { status: "Doing", text: 'say "hi"', type: "Bug", open_only: true })

    assert_equal 'project = 10000 AND issuetype = "Bug" AND status IN (3, 10002) AND summary ~ "say \"hi\"" ' \
                 "AND statusCategory != Done ORDER BY updated DESC", @jira.calls_to(:search).sole[:jql]
  end

  test "a native query's own ordering is kept" do
    @provider.search_issues("10000", { native_query: "assignee = currentUser() order by priority DESC" })

    assert_equal "project = 10000 AND (assignee = currentUser()) ORDER BY priority DESC", @jira.calls_to(:search).sole[:jql]
  end

  test "creating an issue resolves the assignee by name and sets the extra fields" do
    issue = @provider.create_issue("10000", { type: "Bug", title: "Crash", description: "Boom", labels: [ "ai" ],
                                              assignee: "Ada Lovelace", fields: { "priority" => "High", "unknown" => 1 } })

    fields = @jira.calls_to(:create_issue).sole[:fields]
    assert_equal({ project: { id: "10000" }, issuetype: { name: "Bug" }, summary: "Crash", description: "Boom",
                   labels: [ "ai" ], assignee: { accountId: "557058:ada" }, priority: { name: "High" } }, fields)
    assert_equal [ "Crash", "Backlog" ], [ issue.title, issue.status.name ]
  end

  test "an assignee that names more than one person is refused with the candidates" do
    error = assert_raises(Trackers::Error) { @provider.assign_issue("10000", "ENG-1", "Ada") }

    assert_equal [ "validation_failed", [ "Ada Lovelace", "Ada Byron" ] ], [ error.code, error.details[:candidates] ]
  end

  test "assigning by account id or email, and unassigning" do
    @provider.assign_issue("10000", "ENG-1", "ada@example.com")
    @provider.assign_issue("10000", "ENG-1", FakeJira::Api::BOT_ID)
    issue = @provider.assign_issue("10000", "ENG-1", "unassigned")

    assert_equal [ "557058:ada", FakeJira::Api::BOT_ID, nil ], @jira.calls_to(:assign).pluck(:account_id)
    assert_empty issue.assignees
  end

  test "labels are added and removed without rewriting the rest; revisions are refused" do
    @jira.issues["10100"][:labels] = %w[keep old]

    issue = @provider.update_issue("10000", "ENG-1", { labels_add: [ "new" ], labels_remove: [ "old" ], title: "Renamed" })

    assert_equal [ "Renamed", %w[keep new] ], [ issue.title, issue.labels ]
    error = assert_raises(Trackers::Error) { @provider.update_issue("10000", "ENG-1", { title: "x", expected_revision: 3 }) }
    assert_equal "validation_failed", error.code
  end

  test "a transition can name a column, a status or a transition" do
    assert_equal "Doing", @provider.transition_issue("10000", "ENG-1", "doing").status.name
    assert_equal "In Review", @provider.transition_issue("10000", "ENG-1", "In Review").fields["state"]
    assert_equal "Done", @provider.transition_issue("10000", "ENG-1", "Move to Done").status.name
    assert_equal %w[t3 t10002 t10003], @jira.calls_to(:transition).pluck(:transition_id)
  end

  test "moving an issue where it already is changes nothing; somewhere unreachable is refused" do
    @provider.transition_issue("10000", "ENG-1", "Ready for AI")
    error = assert_raises(Trackers::Error) { @provider.transition_issue("10000", "ENG-1", "Shipped") }

    assert_not @jira.called?(:transition)
    assert_equal "validation_failed", error.code
    assert_includes error.details[:allowed], "Done"
  end

  test "a status change within one column moved nothing on the board" do
    issue = @provider.get_issue("10000", "ENG-1")
    within = [ { field: "status", from: "In Progress", to: "In Review", from_id: "3", to_id: "10002" } ]
    across = [ { field: "status", from: "Ready for AI", to: "In Progress", from_id: "10004", to_id: "3" } ]

    assert_nil @provider.status_change(within, issue)
    assert_equal({ "field" => "status", "from" => { "name" => "Ready for AI", "category" => "todo" },
                   "to" => { "name" => "Doing", "category" => "in_progress" },
                   "state" => { "from" => "Ready for AI", "to" => "In Progress" } },
                 @provider.status_change(across, issue))
  end

  test "users are listed for the tracker_list_users tool" do
    assert_equal [ { id: "557058:ada", name: "Ada Lovelace" }, { id: "557058:ada2", name: "Ada Byron" } ],
                 @provider.list_users("10000", query: "ada")
  end

  test "only an account kept for Aixle is its identity" do
    assert @provider.mentions_self?("please [~accountid:#{FakeJira::Api::BOT_ID}] look")

    oauth = Trackers::Provider.for(create(:integration, :jira_oauth, :active))
    assert_nil oauth.identity
    assert_not oauth.own_actor?({ id: FakeJira::Api::BOT_ID })
  end

  test "comments page through, and a new one is posted as text" do
    @provider.add_comment("10000", "ENG-1", "On it")
    page = @provider.list_comments("10000", "ENG-1")

    assert_equal [ [ "On it", "Aixle Bot" ] ], page.items.map { |c| [ c.body, c.author ] }
    assert_not page.has_more?
  end

  test "Jira's refusals keep their code; a write that got no answer stays unknown" do
    @jira.fail_next(:add_comment, Jira::Error::OutcomeUnknown.new("Jira did not answer"))
    assert_raises(Trackers::Error::OutcomeUnknown) { @provider.add_comment("10000", "ENG-1", "x") }

    @jira.fail_next(:issue, Jira::Error.new("Jira denied this operation", code: "permission_denied"))
    assert_equal "permission_denied", assert_raises(Trackers::Error) { @provider.get_issue("10000", "ENG-1") }.code
  end
end
