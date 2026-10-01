# frozen_string_literal: true

require "test_helper"

class Trackers::Github::ProviderTest < ActiveSupport::TestCase
  ROADMAP = FakeGithub::ProjectsApi::ROADMAP

  setup do
    @integration = create(:integration, :github_projects, :active)
    @github = stub_github_projects!
    @provider = Trackers::Provider.for(@integration)
  end

  test "the connection's chosen projects are its scopes, keyed by the project's node id" do
    assert_equal [ [ ROADMAP, "Roadmap" ] ], @provider.scopes.map { |s| [ s.id, s.name ] }
    assert @provider.covers_scope?(ROADMAP)
    assert_not @provider.covers_scope?(FakeGithub::ProjectsApi::OPS)
    assert_equal "github.com", @provider.instance
  end

  test "the statuses are the Status field's options, categorized by their names" do
    description = @provider.describe(ROADMAP)

    assert_equal [ [ "Todo", "todo" ], [ "Ready for AI", "todo" ], [ "In Progress", "in_progress" ], [ "Done", "done" ] ],
                 description[:statuses].map { |s| [ s.name, s.category ] }
    assert_equal %w[Issue Bug], description[:issue_types].pluck(:name)
    assert description[:supports][:native_query]
  end

  test "a project without the configured status field says so" do
    @integration.settings["github_projects"][0]["status_field"] = "Stage"
    @integration.save!

    error = assert_raises(Trackers::Error) { Trackers::Provider.for(@integration).describe(ROADMAP) }
    assert_equal "not_configured", error.code
    assert_match(/no single-select field named Stage/, error.message)
  end

  test "an issue is read by URL, key or node id, with its column as the status" do
    by_url = @provider.get_issue(ROADMAP, "https://github.com/acme-corp/app/issues/1")
    by_key = @provider.get_issue(ROADMAP, "acme-corp/app#1")
    by_id = @provider.get_issue(ROADMAP, "I_kwDOissue1")

    assert_equal [ by_url.id, by_url.key ], [ by_key.id, by_id.key ]
    assert_equal [ "I_kwDOissue1", "acme-corp/app#1", "https://github.com/acme-corp/app/issues/1" ], [ by_url.id, by_url.key, by_url.url ]
    assert_equal [ "Ready for AI", "todo" ], [ by_url.status.name, by_url.status.category ]
    assert_equal({ "repository" => "acme-corp/app", "state" => "open", "item_id" => "PVTI_I_kwDOissue1" }, by_url.fields)
  end

  test "an issue that is not on the tracker's board is not found" do
    error = assert_raises(Trackers::Error) { @provider.get_issue(ROADMAP, "acme-corp/app#2") }

    assert_equal "not_found", error.code
    assert_equal "validation_failed", assert_raises(Trackers::Error) { @provider.get_issue(ROADMAP, "ENG-1") }.code
  end

  test "search filters the board with GitHub's project syntax and leaves draft issues out" do
    page = @provider.search_issues(ROADMAP, { status: "In Progress", labels: [ "ai", "needs review" ], assignee: "@octocat",
                                              open_only: true, text: 'login "fails"', native_query: "repo:acme-corp/app" })

    assert_equal [ "acme-corp/app#1" ], page.items.map(&:key)
    assert_equal '-is:draft status:"In Progress" assignee:octocat label:ai label:"needs review" is:open login fails repo:acme-corp/app',
                 @github.calls_to(:items).last[:query]
  end

  test "transition moves the card to a column by name and refuses a column the board lacks" do
    issue = @provider.transition_issue(ROADMAP, "acme-corp/app#1", "in progress")

    assert_equal "In Progress", issue.status.name
    assert_equal({ project_id: ROADMAP, item_id: "PVTI_I_kwDOissue1", field_id: "PVTSSF_status", option_id: "opt-progress" },
                 @github.calls_to(:set_status).last.except(:method))

    error = assert_raises(Trackers::Error) { @provider.transition_issue(ROADMAP, "acme-corp/app#1", "Shipped") }
    assert_equal "validation_failed", error.code
    assert_equal [ "Todo", "Ready for AI", "In Progress", "Done" ], error.details[:allowed]
  end

  test "a transition to the current column writes nothing" do
    @provider.transition_issue(ROADMAP, "acme-corp/app#1", "Ready for AI")

    assert_not @github.called?(:set_status)
  end

  test "an issue is created in the project's only repository of the organization and put on the board" do
    create(:repository, scope: @integration.project, integration: @integration, full_name: "acme-corp/app")

    issue = @provider.create_issue(ROADMAP, { type: "Bug", title: "New one", description: "Body", labels: [ "ai" ], assignee: "ada" })

    created = @github.calls_to(:create_issue).last
    assert_equal [ "acme-corp/app", "New one", "Body", [ "ada" ], [ "ai" ], "Bug" ],
                 created.values_at(:repository, :title, :body, :assignees, :labels, :type)
    assert_equal ROADMAP, @github.calls_to(:add_to_project).last[:project_id]
    assert_equal [ "New one", "Bug" ], [ issue.title, issue.type ]
  end

  test "creating an issue names the repository when the project has several, and only the organization's" do
    create(:repository, scope: @integration.project, integration: @integration, full_name: "acme-corp/app")
    create(:repository, scope: @integration.project, integration: @integration, full_name: "acme-corp/api")

    error = assert_raises(Trackers::Error) { @provider.create_issue(ROADMAP, { title: "x" }) }
    assert_equal [ "acme-corp/api", "acme-corp/app" ], error.details[:repositories]

    issue = @provider.create_issue(ROADMAP, { title: "x", fields: { "repository" => "acme-corp/api" } })
    assert_equal "Issue", issue.type
    assert_nil @github.calls_to(:create_issue).last[:type]

    other = assert_raises(Trackers::Error) { @provider.create_issue(ROADMAP, { title: "x", fields: { "repository" => "evil/app" } }) }
    assert_match(/not a repository of acme-corp/, other.message)
    assert_equal "validation_failed", assert_raises(Trackers::Error) { @provider.create_issue(ROADMAP, { title: "x", type: "Epic" }) }.code
  end

  test "an issue created but not put on the board is reported as an unknown outcome, never as a failure to retry" do
    @github.fail_next(:add_to_project, Trackers::Error.new("Resource not accessible by integration", code: "permission_denied"))

    error = assert_raises(Trackers::Error::OutcomeUnknown) do
      @provider.create_issue(ROADMAP, { title: "x", fields: { "repository" => "acme-corp/app" } })
    end
    assert_match(%r{Created acme-corp/app#\d+}, error.message)
  end

  test "update edits the issue through its repository and labels one by one" do
    @github.contents["I_kwDOissue1"][:labels] = [ "old" ]

    issue = @provider.update_issue(ROADMAP, "acme-corp/app#1", { title: "Renamed", labels_add: [ "ai" ], labels_remove: [ "old" ],
                                                                 fields: { "state" => "closed" } })

    assert_equal [ "Renamed", [ "ai" ], "closed" ], [ issue.title, issue.labels, issue.fields["state"] ]
    assert_equal "validation_failed", assert_raises(Trackers::Error) { @provider.update_issue(ROADMAP, "acme-corp/app#1", {}) }.code
    assert_equal "validation_failed",
                 assert_raises(Trackers::Error) { @provider.update_issue(ROADMAP, "acme-corp/app#1", { fields: { "state" => "done" } }) }.code
  end

  test "assigning sets the assignee by login, unassigns on none, and reports a login GitHub refused" do
    assert_equal [ "ada" ], @provider.assign_issue(ROADMAP, "acme-corp/app#1", "@ada").assignees
    assert_empty @provider.assign_issue(ROADMAP, "acme-corp/app#1", "none").assignees

    error = assert_raises(Trackers::Error) { @provider.assign_issue(ROADMAP, "acme-corp/app#1", "outsider") }
    assert_match(/only people with access to acme-corp\/app/, error.message)
    assert_equal "unsupported", assert_raises(Trackers::Error) { @provider.list_users(ROADMAP, query: "a") }.code
  end

  test "comments are read and written on the issue" do
    comment = @provider.add_comment(ROADMAP, "acme-corp/app#1", "On it")

    assert_equal [ "I_kwDOissue1", "On it", "aixle-flow[bot]" ], [ comment.issue_id, comment.body, comment.author ]
    assert_equal [ comment.id ], @provider.list_comments(ROADMAP, "acme-corp/app#1").items.map(&:id)
  end

  test "the App's bot account is the connection's identity, and @slug mentions it" do
    assert @provider.own_actor?({ name: "aixle-flow[bot]" })
    assert_not @provider.own_actor?({ name: "octocat" })
    assert @provider.mentions_self?("Hey @aixle-flow, take this")
    assert @provider.mentions_self?("cc @aixle-flow[bot].")
    assert_not @provider.mentions_self?("see @aixle-flow-docs")
  end

  test "an issue reference names this tracker's organization, and resolves to the issue it was written as" do
    assert @provider.owns_reference?(ROADMAP, "https://github.com/acme-corp/app/issues/1")
    assert_not @provider.owns_reference?(ROADMAP, "https://github.com/other/app/issues/1")
    assert_equal "acme-corp/app#7", @provider.issue_identifier("https://github.com/acme-corp/app/pull/7")
    assert_equal "I_kwDOissue1", @provider.issue_identifier("I_kwDOissue1")
    assert_nil @provider.issue_identifier("seven")
  end

  test "a status change from a delivery without option names takes the issue's column" do
    issue = @provider.get_issue(ROADMAP, "I_kwDOissue1")

    assert_equal({ "field" => "status", "from" => { "name" => "Todo", "category" => "todo" },
                   "to" => { "name" => "Ready for AI", "category" => "todo" } },
                 @provider.status_change([ { field: "status", from: "Todo", to: nil } ], issue))
    assert_nil @provider.status_change([ { field: "status", from: "Ready for AI", to: "Ready for AI" } ], issue)
  end
end
