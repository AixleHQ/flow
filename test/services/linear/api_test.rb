# frozen_string_literal: true

require "test_helper"

# Contract tests: the real Linear::Api and Linear::Client against Linear's
# GraphQL payloads. FakeLinear::Api returns the shapes pinned here.
class Linear::ApiTest < ActiveSupport::TestCase
  GRAPHQL = "https://api.linear.app/graphql"

  setup do
    @api = Linear::Api.new(Linear::Client.new(credential: Linear::StaticCredential.api_key("lin_api_key"), retry_delay: 0))
  end

  def stub_graphql(status: 200, data: nil, errors: nil, &matcher)
    request = stub_request(:post, GRAPHQL).with(headers: { "Authorization" => "lin_api_key" })
    request = request.with { |req| matcher.call(JSON.parse(req.body)) } if matcher
    request.to_return(status: status, body: { data: data, errors: errors }.compact.to_json,
                      headers: { "Content-Type" => "application/json" })
  end

  ISSUE = {
    id: "a1b2c3d4-0000-4000-8000-000000000001", identifier: "ENG-1", number: 1, title: "It breaks", description: "Steps",
    url: "https://linear.app/acme/issue/ENG-1/it-breaks", priority: 2, updatedAt: "2026-10-01T10:00:00.000Z",
    team: { id: "team-eng", key: "ENG" }, state: { id: "st-ready", name: "Ready for AI", type: "unstarted" },
    assignee: { id: "u-ada", name: "Ada Lovelace", displayName: "ada", email: "ada@example.com" },
    labels: { nodes: [ { id: "lb-ai", name: "ai" } ] }
  }.freeze

  test "the identity is the viewer and its workspace; an API key is sent without a scheme" do
    stub_graphql(data: { viewer: { id: "u-bot", name: "Aixle Bot", displayName: "aixle", email: "bot@acme.io", app: false },
                         organization: { id: "org-1", name: "Acme", urlKey: "acme" } })

    assert_equal({ id: "u-bot", name: "Aixle Bot", display_name: "aixle", email: "bot@acme.io", app: false,
                   organization: { id: "org-1", name: "Acme", url_key: "acme" } }, @api.identity)
  end

  test "teams come back page by page" do
    stub_graphql(data: { teams: { nodes: [ { id: "t1", key: "ENG", name: "Engineering" } ], pageInfo: { hasNextPage: true, endCursor: "c1" } } }) do |body|
      body.dig("variables", "after").nil?
    end
    stub_graphql(data: { teams: { nodes: [ { id: "t2", key: "OPS", name: "Operations" } ], pageInfo: { hasNextPage: false } } }) do |body|
      body.dig("variables", "after") == "c1"
    end

    assert_equal [ { id: "t1", key: "ENG", name: "Engineering" }, { id: "t2", key: "OPS", name: "Operations" } ], @api.teams
  end

  test "a team's states come back in board order" do
    stub_graphql(data: { team: { states: { nodes: [ { id: "s2", name: "Done", type: "completed", position: 3 },
                                                    { id: "s1", name: "Todo", type: "unstarted", position: 1 } ] } } })

    assert_equal [ { id: "s1", name: "Todo", type: "unstarted" }, { id: "s2", name: "Done", type: "completed" } ], @api.states("t1")
  end

  test "an issue is read by identifier and normalized" do
    stub_graphql(data: { issue: ISSUE }) { |body| body.dig("variables", "id") == "ENG-1" }

    assert_equal({
      id: "a1b2c3d4-0000-4000-8000-000000000001", key: "ENG-1", number: 1, title: "It breaks", description: "Steps",
      url: "https://linear.app/acme/issue/ENG-1/it-breaks", priority: 2, updated_at: "2026-10-01T10:00:00.000Z",
      team_id: "team-eng", team_key: "ENG", state: { id: "st-ready", name: "Ready for AI", type: "unstarted" },
      assignee: { id: "u-ada", name: "Ada Lovelace", display_name: "ada", email: "ada@example.com" },
      labels: [ { id: "lb-ai", name: "ai" } ]
    }, @api.issue("ENG-1"))
  end

  test "an issue Linear does not know is not found" do
    stub_graphql(data: nil, errors: [ { message: "Entity not found: Issue", extensions: { type: "invalid input", userError: true } } ])

    assert_equal "not_found", assert_raises(Trackers::Error) { @api.issue("ENG-404") }.code
  end

  test "throttling, refusals and invalid input keep their meaning" do
    stub_graphql(status: 400, errors: [ { message: "Rate limit exceeded", extensions: { code: "RATELIMITED", type: "ratelimited" } } ])
    assert_equal "rate_limited", assert_raises(Trackers::Error) { @api.teams }.code

    WebMock.reset!
    stub_graphql(errors: [ { message: "Forbidden", extensions: { type: "forbidden", userPresentableMessage: "Only admins can create webhooks" } } ])
    error = assert_raises(Trackers::Error) { @api.create_webhook(url: "https://x", team_id: "t1", secret: "s", label: "Aixle") }
    assert_equal [ "permission_denied", "Only admins can create webhooks" ], [ error.code, error.message ]

    WebMock.reset!
    stub_graphql(status: 400, errors: [ { message: "Argument Validation Error", extensions: { type: "invalid input" } } ])
    assert_equal "validation_failed", assert_raises(Trackers::Error) { @api.update_issue("i1", { stateId: "x" }) }.code
  end

  test "a read is retried after a server error, a write is an unknown outcome" do
    stub_request(:post, GRAPHQL).to_return({ status: 502, body: "" }, { status: 200, body: { data: { issue: ISSUE } }.to_json })
    assert_equal "ENG-1", @api.issue("ENG-1")[:key]

    WebMock.reset!
    stub_request(:post, GRAPHQL).to_return(status: 503, body: "")
    assert_raises(Trackers::Error::OutcomeUnknown) { @api.create_comment("i1", "hi") }
  end

  test "a mutation sends its input and answers what Linear made" do
    stub_graphql(data: { issueCreate: { success: true, issue: ISSUE } }) do |body|
      body.dig("variables", "input") == { "teamId" => "team-eng", "title" => "It breaks", "labelIds" => [ "lb-ai" ] }
    end
    stub_graphql(data: { webhookCreate: { success: true, webhook: { id: "wh-1", enabled: true } } }) do |body|
      body.dig("variables", "input") == { "url" => "https://flow.example.com/webhooks/trackers/t", "teamId" => "team-eng",
                                          "secret" => "s3", "label" => "Aixle", "resourceTypes" => %w[Issue Comment] }
    end

    assert_equal "ENG-1", @api.create_issue({ teamId: "team-eng", title: "It breaks", labelIds: [ "lb-ai" ] })[:key]
    assert_equal "wh-1", @api.create_webhook(url: "https://flow.example.com/webhooks/trackers/t", team_id: "team-eng", secret: "s3", label: "Aixle")
  end
end
