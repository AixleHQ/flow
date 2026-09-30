# frozen_string_literal: true

require "test_helper"

# Contract tests: the real Jira::Api against Jira Cloud's documented payloads.
# FakeJira::Api returns the shapes pinned here.
class Jira::ApiTest < ActiveSupport::TestCase
  setup do
    @api = Jira::Api.new(Jira::Client.new(cloud_id: "cloud-1", credential: Jira::StaticCredential.new("t"), retry_delay: 0))
  end

  def stub_get(*segments, body:, query: nil)
    request = stub_request(:get, jira_url("cloud-1", *segments))
    request = request.with(query: hash_including(query)) if query
    request.to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  test "an issue comes back with its status category, project and assignee" do
    stub_get("api", "2", "issue", "ENG-1", query: { "fields" => Jira::Api::ISSUE_FIELDS }, body: {
      id: "10100", key: "ENG-1", self: "https://api.atlassian.com/ex/jira/cloud-1/rest/api/2/issue/10100",
      fields: {
        summary: "It breaks", description: "Steps: *click*", labels: [ "ai" ], duedate: "2026-10-10",
        issuetype: { id: "1", name: "Task" }, priority: { name: "High" }, parent: { key: "ENG-0" },
        status: { id: "10004", name: "Ready for AI", statusCategory: { id: 2, key: "new", name: "To Do" } },
        project: { id: "10000", key: "ENG", name: "Engineering" },
        assignee: { accountId: "557058:ada", displayName: "Ada Lovelace", emailAddress: "ada@example.com" },
        components: [ { name: "api" } ], created: "2026-09-30T10:00:00.000+0000", updated: "2026-09-30T11:00:00.000+0000"
      }
    })

    assert_equal({
      id: "10100", key: "ENG-1", summary: "It breaks", description: "Steps: *click*", type: "Task",
      status: { id: "10004", name: "Ready for AI", category: "new" }, project: { id: "10000", key: "ENG" },
      assignee: { id: "557058:ada", name: "Ada Lovelace", email: "ada@example.com" }, labels: [ "ai" ],
      priority: "High", due_date: "2026-10-10", parent: "ENG-0", components: [ "api" ],
      created_at: "2026-09-30T10:00:00.000+0000", updated_at: "2026-09-30T11:00:00.000+0000"
    }, @api.issue("ENG-1"))
  end

  test "search pages by Jira's token" do
    stub_get("api", "2", "search", "jql", query: { "jql" => "project = 10000", "maxResults" => "2", "nextPageToken" => "p1" },
             body: { issues: [ { id: "1", key: "ENG-1", fields: { project: { id: "10000" } } } ], nextPageToken: "p2", isLast: false })

    result = @api.search(jql: "project = 10000", limit: 2, cursor: "p1")

    assert_equal [ "ENG-1", "p2" ], [ result[:issues].sole[:key], result[:next_cursor] ]
  end

  test "a board's columns name the statuses they hold" do
    stub_get("agile", "1.0", "board", query: { "projectKeyOrId" => "10000" },
             body: { maxResults: 50, startAt: 0, isLast: true, values: [ { id: 7, name: "ENG board", type: "kanban" } ] })
    stub_get("agile", "1.0", "board", "7", "configuration", body: {
      id: 7, name: "ENG board",
      columnConfig: { columns: [
        { name: "Backlog", statuses: [ { id: "1", self: "…" } ] },
        { name: "Doing", statuses: [ { id: "3", self: "…" }, { id: "10002", self: "…" } ] }
      ], constraintType: "none" }
    })

    assert_equal [ { id: "7", name: "ENG board", type: "kanban" } ], @api.boards("10000")
    assert_equal [ { name: "Backlog", status_ids: [ "1" ] }, { name: "Doing", status_ids: [ "3", "10002" ] } ], @api.board_columns("7")
  end

  test "statuses per issue type, and the transitions an issue can take" do
    stub_get("api", "2", "project", "10000", "statuses", body: [
      { id: "1", name: "Task", subtask: false,
        statuses: [ { id: "3", name: "In Progress", statusCategory: { key: "indeterminate" } } ] }
    ])
    stub_get("api", "2", "issue", "10100", "transitions", body: { transitions: [
      { id: "21", name: "Start", to: { id: "3", name: "In Progress", statusCategory: { key: "indeterminate" } } }
    ] })

    assert_equal [ { issue_type: "Task", statuses: [ { id: "3", name: "In Progress", category: "indeterminate" } ] } ],
                 @api.statuses("10000")
    assert_equal [ { id: "21", name: "Start", to: { id: "3", name: "In Progress", category: "indeterminate" } } ],
                 @api.transitions("10100")
  end

  test "comments page by offset until Jira's total is reached" do
    stub_get("api", "2", "issue", "10100", "comment", query: { "startAt" => "0", "maxResults" => "1" }, body: {
      startAt: 0, maxResults: 1, total: 2,
      comments: [ { id: "5", body: "first [~accountid:557058:ada]", author: { displayName: "Ada" }, created: "2026-09-30T10:00:00.000+0000" } ]
    })

    page = @api.comments("10100", limit: 1)

    assert_equal [ { id: "5", author: "Ada", body: "first [~accountid:557058:ada]", created_at: "2026-09-30T10:00:00.000+0000" } ],
                 page[:comments]
    assert_equal "1", page[:next_cursor]
  end

  test "projects follow Jira's offset pages" do
    stub_get("api", "2", "project", "search", query: { "startAt" => "0" },
             body: { isLast: false, values: [ { id: "10000", key: "ENG", name: "Engineering" } ] })
    stub_get("api", "2", "project", "search", query: { "startAt" => "1" },
             body: { isLast: true, values: [ { id: "10001", key: "OPS", name: "Operations" } ] })

    assert_equal %w[ENG OPS], @api.projects.pluck(:key)
  end

  test "registering a webhook answers its id, or why Jira would not" do
    stub_request(:post, jira_url("cloud-1", "api", "3", "webhook"))
      .with(body: { url: "https://flow.example.com/webhooks/trackers/app/jira",
                    webhooks: [ { jqlFilter: "project IN (10000)", events: [ "jira:issue_created" ] } ] }.to_json)
      .to_return({ status: 200, body: { webhookRegistrationResult: [ { createdWebhookId: 1000 } ] }.to_json },
                 { status: 200, body: { webhookRegistrationResult: [ { errors: [ "Only 5 webhooks per user" ] } ] }.to_json })
    register = -> { @api.register_webhook(url: "https://flow.example.com/webhooks/trackers/app/jira", jql: "project IN (10000)", events: [ "jira:issue_created" ]) }

    assert_equal "1000", register.call
    assert_match(/Only 5 webhooks/, assert_raises(Jira::Error) { register.call }.message)
  end

  test "refreshing webhooks answers their new expiry" do
    stub_request(:put, jira_url("cloud-1", "api", "3", "webhook", "refresh")).with(body: { webhookIds: [ 1000 ] }.to_json)
      .to_return(status: 200, body: { expirationDate: "2026-10-30T09:00:00.000+0000" }.to_json)

    assert_equal Time.zone.parse("2026-10-30T09:00:00Z"), @api.refresh_webhooks([ "1000" ])
  end
end
